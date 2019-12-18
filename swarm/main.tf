#############################################################
##
## This app file contains the bootstrap of Swarm Installation
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

variable "workers" {
  default = 3
}

# Load the latest Ubuntu AMI
data "aws_ami" "default" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

module "aws_networking" {
  source = "../modules/network"
}

resource "aws_instance" "master" {
  tags = {
    Name = "master"
  }
  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.private_key_path)
  }
  associate_public_ip_address = true
  private_ip                  = "10.0.1.10"
  instance_type               = "t2.medium"
  ami                         = data.aws_ami.default.id
  key_name                    = var.key_name
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
    volume_size = "20"
  }
  provisioner "file" {
    source      = var.private_key_path
    destination = "/home/ubuntu/.ssh/id_rsa"
  }
  provisioner "file" {
    source      = "files/hosts"
    destination = "/tmp/hosts"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "sudo chmod 600 /home/ubuntu/.ssh/id_rsa",
      "sudo cat /tmp/hosts | sudo tee --append /etc/hosts",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker.io; sleep 2; done",
      "wait",
      "sudo docker swarm init",
      "sudo docker swarm join-token --quiet worker > /home/ubuntu/token",
      "sudo groupadd docker",
      "sudo gpasswd -a ubuntu docker",
      "sudo docker run --restart=always --name px-lighthouse -d -p 80:80 -p 443:443 -v /etc/pwxlh:/config portworx/px-lighthouse:2.0.1",
    ]
  }
}

resource "random_string" "cluster_id" {
  length  = 12
  special = false
  upper   = false
}

resource "aws_instance" "worker" {
  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.private_key_path)
  }
  depends_on    = [aws_instance.master]
  count         = var.workers
  instance_type = "t2.medium"
  tags = {
    Name = "worker-${count.index + 1}"
  }
  private_ip = "10.0.1.1${count.index + 1}"
  ami        = data.aws_ami.default.id
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
    volume_size = "20"
  }
  ebs_block_device {
    device_name = "/dev/sdd"
    volume_type = "gp2"
    volume_size = "30"
  }
  provisioner "file" {
    source      = "files/hosts"
    destination = "/tmp/hosts"
  }
  provisioner "file" {
    source      = var.private_key_path
    destination = "/home/ubuntu/.ssh/id_rsa"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "sudo chmod 600 /home/ubuntu/.ssh/id_rsa",
      "sudo cat /tmp/hosts | sudo tee --append /etc/hosts",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker.io; sleep 2; done",
      "sudo scp -i /home/ubuntu/.ssh/id_rsa -o StrictHostKeyChecking=no -o NoHostAuthenticationForLocalhost=yes -o UserKnownHostsFile=/dev/null ubuntu@${aws_instance.master.private_ip}:/home/ubuntu/token .",
      "sudo docker swarm join --token $(cat /home/ubuntu/token) ${aws_instance.master.private_ip}:2377",
      "latest_stable=$(curl -fsSL 'https://install.portworx.com/2.0/?type=dock&stork=false' | awk '/image: / {print $2}')",
      "sudo docker run --entrypoint /runc-entry-point.sh --rm -i --privileged=true -v /opt/pwx:/opt/pwx -v /etc/pwx:/etc/pwx $latest_stable",
      "sudo /opt/pwx/bin/px-runc install -c px-${random_string.cluster_id.result} -k etcd:http://px-eu-etcd1.portworx.com:2379 -s /dev/xvdd -m eth0 -d eth0",
      "sleep 10",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable portworx",
      "sudo systemctl start portworx",
      "sudo groupadd docker",
      "sudo gpasswd -a ubuntu docker",
    ]
  }
}

output "master_access" {
  value = ["ssh ubuntu@${aws_instance.master.public_ip}"]
}

output "master-lighthouse" {
  value = "${aws_instance.master.public_ip}:80/login"
}

