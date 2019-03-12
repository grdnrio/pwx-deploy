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
  region = "${var.aws_region}"
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
    Name = "master"
  }

  connection {
    # The default username for our AMI
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  associate_public_ip_address = true
  private_ip = "10.0.1.10"
  instance_type = "t2.medium"
  # Lookup the correct AMI based on the region
  # we specified
  ami = "${data.aws_ami.default.id}"

  # The name of our SSH keypair we created above.
  key_name = "${var.key_name}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.default.id}"

  root_block_device = {
    volume_type = "gp2"
    volume_size = "20"
  }

  provisioner "file" {
    source      = "${var.private_key_path}"
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
      "sudo docker run --restart=always --name px-lighthouse -d -p 80:80 -p 443:443 -v /etc/pwxlh:/config portworx/px-lighthouse:2.0.1"
    ]
  }
}

resource "random_string" "cluster_id" {
  length = 12
  special = false
  upper = false
}

resource "aws_instance" "worker" {
  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }
  depends_on = ["aws_instance.master"]
  count = "${var.workers}"
  instance_type = "t2.medium"
  tags = {
    Name = "worker-${count.index +1}"
  }
  private_ip = "10.0.1.1${count.index +1}"
  ami = "${data.aws_ami.default.id}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.default.id}"
  root_block_device = {
    volume_type = "gp2"
    volume_size = "20"
  }
  ebs_block_device = {
    device_name = "/dev/sdd"
    volume_type = "gp2"
    volume_size = "30"
  }
  provisioner "file" {
    source      = "files/hosts"
    destination = "/tmp/hosts"
  }
  provisioner "file" {
    source      = "${var.private_key_path}"
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
      "sudo gpasswd -a ubuntu docker"
    ]
  }
}

output "master-lighthouse" {
  value = "${aws_instance.master.public_ip}:80/login"
}