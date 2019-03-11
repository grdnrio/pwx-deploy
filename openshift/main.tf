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

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "terraform_sg_default"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 35000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self = true
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "master" {
  
  tags = {
    Name = "master-${ count.index + 1 }"
  }

  connection {
    user = "centos"
    private_key = "${file(var.private_key_path)}"
  }

  associate_public_ip_address = true
  private_ip = "10.0.1.10"

  instance_type = "t2.large"
  ami = "${data.aws_ami.centos.id}"

  key_name = "${var.key_name}"

  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.default.id}"

  root_block_device = {
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

      # Repo
      "cd ~ && git clone https://github.com/grdnrio/sa-toolkit.git",
    ]
  }
}

resource "aws_instance" "worker" {
  connection {
    user = "centos"
    private_key = "${file(var.private_key_path)}"
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
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.default.id}"
  root_block_device = {
    volume_type = "gp2"
    volume_size = "80"
  }
  ebs_block_device = {
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
  vars {
    master_public_ip = "${aws_instance.master.public_ip}"
  }
}

resource "null_resource" "inventory" {
  triggers {
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
  triggers {
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


output "master1_access" {
    value = ["ssh centos@${aws_instance.master.public_ip}"]
}

output "openshift_dashboard" {
    value = ["https://${aws_instance.master.public_ip}:8443/console"]
}

output "grafana_url" {
    value = ["http://${aws_instance.worker.0.public_ip}:30950"]
}
