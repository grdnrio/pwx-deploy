#############################################################
##
## This app file contains the bootstrap of OpenShift Installation
## on AWS
## 
## @year 2019
## @author Joe Gardiner <joe@grdnr.io>
##
#############################################################

# Specify the provider and access details
provider "aws" {
  region = "${var.aws_region}"
  version = "~> 2.0"
}


# Load the latest Centos AMI
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
    Name = "master"
  }

  connection {
    user = "centos"
    private_key = "${file(var.private_key_path)}"
    host = "${self.public_ip}" 
  }

  associate_public_ip_address = true
  private_ip = "10.0.1.10"

  instance_type = "t2.large"
  ami = "${data.aws_ami.centos.id}"

  key_name = "${var.key_name}"

  vpc_security_group_ids = ["${module.aws_networking.security_group}"]
  subnet_id = "${module.aws_networking.subnet}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "100"
  }

  provisioner "file" {
    source      = "files"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = "${var.private_key_path}"
    destination = "/home/centos/.ssh/id_rsa"
  }
   provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "sudo chmod 600 /home/centos/.ssh/id_rsa",
      "sudo cat /tmp/files/hosts | sudo tee --append /etc/hosts",
      
      # Pre-requisites
      "sudo yum -y install git epel-release", 
      "sudo yum -y install python-pip",
      "sudo pip install ansible",
      "cd ~ && git clone https://github.com/openshift/openshift-ansible",
      "mv /tmp/prepare.yaml openshift-ansible/.",

      # Repo
      "cd ~ && git clone https://github.com/grdnrio/sa-toolkit.git",
    ]
  }
}

resource "aws_instance" "worker" {
  connection {
    user = "centos"
    private_key = "${file(var.private_key_path)}"
    host = "${self.public_ip}"
  }
  depends_on = ["aws_instance.master"]
  count = "3"
  instance_type = "t2.medium"
  tags = {
    Name = "worker-${ count.index +1 }"
  }
  private_ip = "10.0.1.1${ count.index +1 }"
  ami = "${data.aws_ami.centos.id}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${module.aws_networking.security_group}"]
  subnet_id = "${module.aws_networking.subnet}"
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
    source      = "files/hosts"
    destination = "/tmp/hosts"
  }
  provisioner "file" {
    source      = "${var.private_key_path}"
    destination = "/home/centos/.ssh/id_rsa"
  }
   provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "sudo chmod 600 /home/centos/.ssh/id_rsa",
      "sudo cat /tmp/files/hosts | sudo tee --append /etc/hosts",
    ]
  }
}

data "template_file" "inventory" {
  template = "${file("files/inventory.tpl")}"
  depends_on = ["aws_instance.worker"]
  vars  = {
    master_public_ip = "${aws_instance.master.public_ip}"
  }
}

resource "null_resource" "inventory" {
  triggers = {
    template_rendered = "${data.template_file.inventory.rendered}"
  }
  connection {
    user = "centos"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.public_ip}"
  }
  provisioner "file" {
    content      = "${data.template_file.inventory.rendered}"
    destination = "/tmp/inventory"
  }
}

resource "null_resource" "ansible" {
  triggers = {
    version = "${timestamp()}"
  }
  depends_on = ["null_resource.inventory"]
  connection {
    user = "centos"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.public_ip}"
  }
  provisioner "remote-exec" {
    inline = [
      "cd openshift-ansible",
      "git checkout release-3.11",
      "ansible-playbook /tmp/files/prepare.yaml -i /tmp/inventory",
      "ansible-playbook playbooks/prerequisites.yml -i /tmp/inventory",
      "ansible-playbook playbooks/deploy_cluster.yml -i /tmp/inventory"
    ]
  }
}


resource "null_resource" "portworx" {
  triggers = {
    version = "${timestamp()}"
  }
  depends_on = ["null_resource.ansible"]
  connection {
    user = "centos"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.public_ip}"
  }
  provisioner "remote-exec" {
    inline = [
      "sleep 10",
      "oc login -u system:admin -n default",
      "sleep 5",
      "oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:px-account",
      "oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:portworx-pvc-controller-account",
      "oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:px-lh-account",
      "oc adm policy add-scc-to-user anyuid system:serviceaccount:kube-system:px-lh-account",
      "oc adm policy add-scc-to-user anyuid system:serviceaccount:default:default",
      "oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:px-csi-account",
      "sleep 5",
      "oc apply -f 'https://install.portworx.com/2.0?mc=false&kbver=1.11.0&b=true&s=%2Fdev%2Fxvdd&m=eth0&d=eth0&c=px-cluster-963cade8-8920-4000-a03d-2c8b0fb98727&osft=true&stork=true&lh=true&st=k8s'"
    ]
  }
}


output "master1_access" {
    value = ["ssh centos@${aws_instance.master.public_ip}  then run oc login -u system:admin -n default"]
}

output "openshift_dashboard" {
    value = ["https://${aws_instance.master.public_ip}:8443/console    -   admin:admin"]
}
