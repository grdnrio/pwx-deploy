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
  region = "${var.aws_region}"
}

variable "clusters" {
  type = "list"
  default = ["1", "2"]
}

variable "workers" {
  type = "list"
  default = ["1", "2", "3"]
}

variable "join_token" {
  type= "string"
  default = "abcdef.1234567890abcdef"
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
    Name = "master-${count.index + 1}"
  }
  
  count = "${length(var.clusters)}"

  connection {
    # The default username for our AMI
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  associate_public_ip_address = true
  private_ip = "10.0.1.${count.index + 1}0"

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
    source      = "files/"
    destination = "/tmp"
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
      "git clone https://github.com/grdnrio/sa-toolkit.git",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add",
      "sudo echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee --append /etc/apt/sources.list.d/kubernetes.list",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker.io; sleep 2; done",
      "sudo apt-get install -y kubeadm",
      "sudo systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "sudo kubeadm config images pull",
      "wait",
      "sudo kubeadm init --apiserver-advertise-address=${self.private_ip} --pod-network-cidr=10.244.0.0/16 --node-name ${self.tags.Name}",
      "sudo kubeadm token create ${var.join_token}",
      "sudo mkdir /root/.kube /home/ubuntu/.kube /tmp/grafanaConfigurations",
      "sudo cp /etc/kubernetes/admin.conf /root/.kube/config && sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config",
      "sudo chown -R ubuntu.ubuntu /home/ubuntu/.kube",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml",
      "kubectl apply -f 'https://install.portworx.com/2.0?kbver=1.13.1&b=true&m=eth0&d=eth0&c=px-demo-${count.index + 1}&stork=true&st=k8s&lh=true'",
      
      # Helm installation
      "sudo snap install helm --classic",
      "kubectl apply -f /tmp/tiller-rbac.yaml",
      ". ~/.profile",
      "sudo helm init --service-account tiller",

      # Grafana installation
 /*      "sudo mkdir -p /var/lib/grafana/dashboards",
      "sudo curl -o /var/lib/grafana/dashboards/cluster.json -s https://docs.portworx.com/install-with-other/operate-and-maintain/monitoring/grafana/Cluster_Template.json",
      "curl -o /tmp/dashboardConfig.yaml -s https://raw.githubusercontent.com/portworx/px-docs/gh-pages/k8s-samples/grafana/config/dashboardConfig.yaml",
      "kubectl create configmap grafana-config --from-file=/tmp -n kube-system",
      "kubectl apply -f /tmp/grafana-deployment.yaml", */
      
      # Stork binary installation
      "sudo curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/2.0.0/linux/storkctl -o /usr/bin/storkctl && sudo chmod +x /usr/bin/storkctl",

    ]
  }
}

resource "null_resource" "storkctl" {

  connection {
    # The default username for our AMI
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.1.public_ip}"
  }
  triggers {
        build_number = "${timestamp()}"
  }

  depends_on = ["aws_instance.worker", "aws_instance.master"]

  provisioner "remote-exec" {
    inline = [
      "sleep 180",
      "token=$(ssh -oStrictHostKeyChecking=no worker-2-1 pxctl cluster token show | cut -f 3 -d ' ')",
      "echo $token | grep -Eq '.{128}'",
      "storkctl generate clusterpair -n default remotecluster | sed '/insert_storage_options_here/c\\    ip: worker-2-1\\n    token: '$token >/home/ubuntu/cp.yaml",
      "cat /home/ubuntu/cp.yaml | ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no master-1 kubectl apply -f -"
    ] 
  }
}

resource "aws_instance" "worker" {
  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }
  depends_on = ["aws_instance.master"]
  count = "${length(var.clusters) * length(var.workers)}"
  instance_type = "t2.medium"
  tags = {
    Name = "worker-${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
  }
  private_ip = "10.0.1.${var.clusters[count.index % length(var.clusters)]}${var.workers[count.index % length(var.workers)]}"
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
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add",
      "sudo echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee --append /etc/apt/sources.list.d/kubernetes.list",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker.io; sleep 2; done",
      "wait",
      "sudo apt-get install -y kubeadm",
      "sudo systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "sudo kubeadm config images pull",
      "sudo docker pull portworx/oci-monitor:2.0.1 ; sudo docker pull openstorage/stork:2.0.1 ; sudo docker pull portworx/px-enterprise:2.0.1",
      "sudo kubeadm join 10.0.1.${var.clusters[count.index % length(var.clusters)]}0:6443 --token ${var.join_token} --discovery-token-unsafe-skip-ca-verification --node-name ${self.tags.Name}"
    ]
  }
}

resource "null_resource" "prometheus" {

  connection {
    # The default username for our AMI
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.*.public_ip}"
  }
  triggers {
        build_number = "${timestamp()}"
  }

  depends_on = ["aws_instance.worker"]

  provisioner "remote-exec" {
    inline = [
      "kubectl apply -f /tmp/prometheus-operator.yaml",
      "kubectl create secret generic alertmanager-portworx --from-file=/tmp/alertmanager.yaml -n kube-system",
      "while : ; do kubectl apply -f /tmp/service-monitor.yaml; [ $? -eq 0 ] && break; done",
      "kubectl apply -f /tmp/alertmanager-cluster.yaml",
      "kubectl apply -f /tmp/alertmanager-service.yaml",
      "kubectl apply -f /tmp/prometheus-rules.yaml",
      "kubectl apply -f /tmp/prometheus-cluster.yaml"
    ] 
  }
}

