#############################################################
##
## This app file contains the bootstrap of Kubernetes Installation
## on AWS
## 
## @year 2019
## @author Joe Gardiner <joe@grdnr.io>
##
#############################################################

# Specify the provider and access details
provider "aws" {
  region = var.aws_region
}

variable "join_token" {
  type    = string
  default = "abcdef.1234567890abcdef"
}

data "aws_ami" "centos" {
  owners      = ["679593333241"]
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS Linux 7 x86_64 HVM EBS *"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

module "aws_networking" {
  source = "../modules/network"
}

resource "aws_instance" "master" {
  tags = {
    Name = "master-${count.index + 1}"
  }

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "centos"
    private_key = file(var.private_key_path)
  }

  associate_public_ip_address = true
  private_ip                  = "10.0.1.10"

  instance_type = "t2.large"
  ami           = data.aws_ami.centos.id

  key_name = var.key_name

  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibility in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  vpc_security_group_ids = [module.aws_networking.security_group]
  subnet_id              = module.aws_networking.subnet

  root_block_device {
    volume_type = "gp2"
    volume_size = "100"
  }

  provisioner "file" {
    source      = "files"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = var.private_key_path
    destination = "/home/centos/.ssh/id_rsa"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "sudo chmod 600 /home/centos/.ssh/id_rsa",
      "sudo cat /tmp/files/hosts | sudo tee --append /etc/hosts",
      "sudo curl -fsSL https://get.docker.com/ | sh",
      "sudo systemctl start docker",
      "sudo curl https://github.com/rancher/rke/releases/download/v0.1.17/rke_linux-amd64 -o /usr/bin/rke",
    ]
  }
}

resource "aws_instance" "worker" {
  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "centos"
    private_key = file(var.private_key_path)
  }
  depends_on    = [aws_instance.master]
  count         = "3"
  instance_type = "t2.medium"
  tags = {
    Name = "worker-${count.index + 1}"
  }
  private_ip = "10.0.1.1${count.index + 1}"
  ami        = data.aws_ami.centos.id
  key_name   = var.key_name
  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibility in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  vpc_security_group_ids = [module.aws_networking.security_group]
  subnet_id              = module.aws_networking.subnet
  root_block_device {
    volume_type = "gp2"
    volume_size = "80"
  }
  ebs_block_device {
    device_name = "/dev/sdd"
    volume_type = "gp2"
    volume_size = "50"
  }
  provisioner "file" {
    source      = "files"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = var.private_key_path
    destination = "/home/centos/.ssh/id_rsa"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "sudo chmod 600 /home/centos/.ssh/id_rsa",
      "sudo cat /tmp/files/hosts | sudo tee --append /etc/hosts",
      "sudo curl -fsSL https://get.docker.com/ | sh",
      "sudo systemctl start docker",
    ]
  }
}

data "template_file" "cluster" {
  template   = file("files/cluster.tpl")
  depends_on = [aws_instance.worker]
  vars = {
    master_public_ip  = aws_instance.master.public_ip
    worker1_public_ip = aws_instance.worker[0].public_ip
    worker2_public_ip = aws_instance.worker[1].public_ip
    worker3_public_ip = aws_instance.worker[2].public_ip
  }
}

resource "null_resource" "cluster-file" {
  triggers = {
    template_rendered = data.template_file.cluster.rendered
  }
  connection {
    user        = "centos"
    private_key = file(var.private_key_path)
    host        = aws_instance.master.public_ip
  }
  provisioner "file" {
    content     = data.template_file.cluster.rendered
    destination = "/tmp/rancher-cluster.yaml"
  }
}

resource "null_resource" "deploy" {
  triggers = {
    version = timestamp()
  }
  depends_on = [null_resource.cluster-file]
  connection {
    user        = "centos"
    private_key = file(var.private_key_path)
    host        = aws_instance.master.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "rke up --config /tmp/rancher-cluster.yaml",
    ]
  }
}

# resource "null_resource" "rancher_install" {

#   connection {
#     user = "ubuntu"
#     private_key = "${file(var.private_key_path)}"
#     host = "${aws_instance.master.public_ip}"
#   }
#   triggers {
#     build_number = "${timestamp()}"
#   }

#   depends_on = ["aws_instance.worker", "aws_instance.master"]

#   provisioner "remote-exec" {
#     inline = [
#       # Rancher installation
#       "kubectl rollout status -w deployment/tiller-deploy --namespace=kube-system",
#       "sudo helm repo add rancher-stable https://releases.rancher.com/server-charts/stable",
#       "sudo helm install stable/cert-manager --name cert-manager --namespace kube-system --version v0.5.2",
#       "sudo helm install rancher-stable/rancher --name rancher --namespace cattle-system --set hostname=rancher.${aws_instance.master.public_ip}.xip.io"
#     ] 
#   }
# }

output "master1_access" {
  value = ["ssh ubuntu@${aws_instance.master.public_ip}"]
}

output "rancher_dashboard" {
  value = ["http://rancher.${aws_instance.master.public_ip}.xip.io"]
}

output "grafana_url" {
  value = ["http://${aws_instance.worker[0].public_ip}:31522"]
}

