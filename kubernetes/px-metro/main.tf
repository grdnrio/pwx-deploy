#############################################################
##
## This app file contains the bootstrap of Kubernetes Installation
## on AWS with px-metro configured
## 
## @year 2019
## @author Joe Gardiner <joe@grdnr.io>
##
#############################################################


# terraform {
#   backend "remote" {
#     hostname = "app.terraform.io"
#     organization = "Portworx-Demos"

#     workspaces {
#       name = "metro-demo"
#     }
#   }
# }


# Specify the provider and access details
provider "aws" {
  region = "${var.aws_region}"
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


### NETWORKING
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
resource "aws_subnet" "eu-west-c1" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-2a"
}

resource "aws_subnet" "eu-west-c2" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-2c"
}

resource "aws_subnet" "etcd" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.3.0/24"
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
    from_port   = 9020
    to_port     = 9021
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

### END NETWORKING






resource "aws_instance" "etcd" {
  
  tags = {
    Name = "etcd"
  }

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  associate_public_ip_address = true
  private_ip = "10.0.3.10"

  instance_type = "t2.medium"
  ami = "${data.aws_ami.default.id}"
  key_name = "${var.key_name}"

  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.etcd.id}"

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
      "sudo curl -fsSL https://github.com/coreos/etcd/releases/download/v3.3.8/etcd-v3.3.8-linux-amd64.tar.gz | sudo tar -xvz --strip=1 -f - -C /usr/local/bin etcd-v3.3.8-linux-amd64/etcdctl etcd-v3.3.8-linux-amd64/etcd",
      "sudo useradd -d /var/lib/etcd -s /bin/false -m etcd",
      "sudo cp /tmp/etcd.service /lib/systemd/system/etcd.service",
      "sudo systemctl enable etcd",
      "sudo systemctl restart etcd",
      "wait"      
    ]
  }
}

resource "aws_instance" "master-c1" {
  tags = {
    Name = "master-c1"
  }

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  availability_zone = "eu-west-2a"
  associate_public_ip_address = true
  private_ip = "10.0.1.10"

  instance_type = "t2.medium"
  ami = "${data.aws_ami.default.id}"

  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.eu-west-c1.id}"

  root_block_device = {
    volume_type = "gp2"
    volume_size = "20"
  }

  provisioner "file" {
    source      = "files/"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = "../../apps/"
    destination = "/tmp/apps"
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
      
      # Install Docker
      "sudo apt-get remove docker docker-engine docker.io containerd runc",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sleep 10",
      "until find /etc/apt/ -name *.list | xargs cat | grep  ^[[:space:]]*deb | grep docker; do sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"; sleep 2; done",
      "wait",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io; sleep 2; done",

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
      "kubectl apply -f https://2.0.docs.portworx.com/samples/k8s/portworx-pxc-operator.yaml",
      "sleep 60",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/alertmanager.crd.yaml",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/prometheus.crd.yaml",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/prometheusrule.crd.yaml",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/servicemonitor.crd.yaml",
      "sleep 30",
      "kubectl apply -f https://docs.portworx.com/samples/k8s/portworx-pxc-operator.yaml",
      "kubectl create secret generic alertmanager-portworx --from-file=/tmp/portworx-pxc-alertmanager.yaml -n kube-system",
      "kubectl apply -f 'https://install.portworx.com/2.1?mc=false&kbver=1.13.3&k=etcd%3Ahttp%3A%2F%2F10.0.3.10%3A2379&c=px-demo&stork=true&st=k8s'",
      "kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml",
      "sleep 10",
      "sudo apt-get update && sudo apt-get install -y jq && hash -r",
      "sudo bash /tmp/patch.sh cluster-1",
      # Stork binary installation
      "sudo curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/latest/linux/storkctl -o /usr/bin/storkctl && sudo chmod +x /usr/bin/storkctl",

    ]
  }
}

resource "aws_instance" "master-c2" {
  tags = {
    Name = "master-c2"
  }

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  availability_zone = "eu-west-2c"
  associate_public_ip_address = true
  private_ip = "10.0.2.10"

  instance_type = "t2.medium"
  ami = "${data.aws_ami.default.id}"

  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.eu-west-c2.id}"

  root_block_device = {
    volume_type = "gp2"
    volume_size = "20"
  }

  provisioner "file" {
    source      = "files/"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = "../../apps/"
    destination = "/tmp/apps"
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
      
      # Install Docker
      "sudo apt-get remove docker docker-engine docker.io containerd runc",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sleep 10",
      "until find /etc/apt/ -name *.list | xargs cat | grep  ^[[:space:]]*deb | grep docker; do sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"; sleep 2; done",
      "wait",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io; sleep 2; done",

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
      "kubectl apply -f https://docs.portworx.com/samples/k8s/portworx-pxc-operator.yaml",
      "kubectl create secret generic alertmanager-portworx --from-file=/tmp/portworx-pxc-alertmanager.yaml -n kube-system",
      "kubectl apply -f 'https://install.portworx.com/2.1?mc=false&kbver=1.13.3&k=etcd%3Ahttp%3A%2F%2F10.0.3.10%3A2379&c=px-demo&stork=true&st=k8s'",
      "kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml",
      "sleep 10",
      "sudo apt-get update && sudo apt-get install -y jq && hash -r",
      "sudo bash /tmp/patch.sh cluster-2",
      # Stork binary installation
      "sudo curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/latest/linux/storkctl -o /usr/bin/storkctl && sudo chmod +x /usr/bin/storkctl",

    ]
  }
}

resource "aws_instance" "worker-c1" {
  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }
  depends_on = ["aws_instance.master-c1"]
  count = "3"
  instance_type = "t2.medium"
  tags = {
    Name = "worker-c1-${ count.index +1 }"
  }
  availability_zone = "eu-west-2a"
  private_ip = "10.0.1.1${ count.index +1 }"
  ami = "${data.aws_ami.default.id}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.eu-west-c1.id}"
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
      
      # Install Docker
      "sudo apt-get remove docker docker-engine docker.io containerd runc",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sleep 10",
      "until find /etc/apt/ -name *.list | xargs cat | grep  ^[[:space:]]*deb | grep docker; do sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"; sleep 2; done",
      "wait",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io; sleep 2; done",

      "wait",
      "sudo apt-get install -y kubeadm",
      "sudo systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "sudo kubeadm config images pull",
      "sudo kubeadm join 10.0.1.10:6443 --token ${var.join_token} --discovery-token-unsafe-skip-ca-verification --node-name ${self.tags.Name}"
    ]
  }
}

resource "aws_instance" "worker-c2" {
  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }
  depends_on = ["aws_instance.master-c2"]
  count = "3"
  instance_type = "t2.medium"
  tags = {
    Name = "worker-c2-${ count.index +1 }"
  }
  availability_zone = "eu-west-2c"
  private_ip = "10.0.2.1${ count.index +1 }"
  ami = "${data.aws_ami.default.id}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.eu-west-c2.id}"
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
      
      # Install Docker
      "sudo apt-get remove docker docker-engine docker.io containerd runc",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sleep 10",
      "until find /etc/apt/ -name *.list | xargs cat | grep  ^[[:space:]]*deb | grep docker; do sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"; sleep 2; done",
      "wait",
      "until docker; do sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io; sleep 2; done",

      "wait",
      "sudo apt-get install -y kubeadm",
      "sudo systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "sudo kubeadm config images pull",
      "sudo kubeadm join 10.0.2.10:6443 --token ${var.join_token} --discovery-token-unsafe-skip-ca-verification --node-name ${self.tags.Name}"
    ]
  }
}

resource "aws_elb" "k8s-app" {
  name = "px-metro-demo"
  subnets = ["${aws_subnet.eu-west-c1.id}", "${aws_subnet.eu-west-c2.id}"]
  security_groups = ["${aws_security_group.default.id}"]
  listener {
    instance_port     = 30333
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:30333/"
    interval            = 5
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400

  instances                   = ["${aws_instance.worker-c1.*.id}", "${aws_instance.master-c1.id}", "${aws_instance.worker-c2.*.id}", "${aws_instance.master-c2.id}"]

  tags = {
    Name = "px-metro-demo-lb"
  }
}


resource "null_resource" "storkctl" {

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master-c1.public_ip}"
  }
  triggers {
    build_number = "${timestamp()}"
  }

  depends_on = ["aws_instance.master-c2", "aws_instance.worker-c2"]

  provisioner "remote-exec" {
    inline = [
<<EOF
if ssh -oStrictHostKeyChecking=no worker-c2-1 bash -c 'kubectl' ; then
  while : ; do
    token=$(ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no worker-c2-1 pxctl cluster token show | cut -f 3 -d " ")
    echo $token | grep -Eq '.{128}'
    [ $? -eq 0 ] && break
    echo "Waiting for the pxctl binary"
    sleep 5
  done
  ssh -oStrictHostKeyChecking=no master-c2 storkctl generate clusterpair -n default remotecluster | sed '/insert_storage_options_here/c\    mode: DisasterRecovery' >/home/ubuntu/cp.yaml
  kubectl apply -f /home/ubuntu/cp.yaml
else
  echo "Nothing to do. Single cluster deployment"
fi
while : ; do
    status=$(curl worker-c1-1:9001/status | jq '.StorageSpec."Info" | .Status')
    [ "$status" = "\"Up\"" ] && break
    echo "Waiting for PWX quorum"
    sleep 3
done
sleep 20
ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no worker-c1-1 pxctl license activate --ep UAT 9035-1a42-beb4-41f7-a4c0-9af0-ccd9-dab6
sleep 5
ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no worker-c1-1 pxctl license activate --ep UAT 44ce-190f-3273-485c-b7a6-730f-98fc-8535
sleep 5
kubectl apply -f /tmp/sched-policy.yaml
sleep 60
EOF
    ]
  }
}

resource "null_resource" "appdeploy" {

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master-c1.public_ip}"
  }
  triggers {
    build_number = "${timestamp()}"
  }

  depends_on = ["null_resource.storkctl"]

  provisioner "remote-exec" {
    inline = [
      # Deploy demo app
      "kubectl apply -f /tmp/apps/petclinic-db.yaml",
      "kubectl apply -f /tmp/apps/petclinic-deployment.yaml",
      "kubectl apply -f /tmp/migration-sched.yaml"
    ] 
  }
}


# resource "aws_cloudwatch_event_rule" "cluster1-delete" {
#   name        = "cluster1-delete"
#   description = "Capture the master in cluster1 being terminated"

#   event_pattern = <<PATTERN
# {
#   "source": [
#     "aws.ec2"
#   ],
#   "detail-type": [
#     "EC2 Instance State-change Notification"
#   ],
#   "detail": {
#     "state": [
#       "shutting-down",
#       "stopping"
#     ],
#     "instance-id": [
#       "${aws_instance.master.0.id}"
#     ]
#   }
# }
# PATTERN
# }

# resource "aws_cloudwatch_metric_alarm" "cluster-1" {
#   alarm_name                = "cluster-1-down"
#   comparison_operator       = "GreaterThanOrEqualToThreshold"
#   evaluation_periods        = "2"
#   metric_name               = "CPUUtilization"
#   namespace                 = "AWS/ELB"
#   period                    = "120"
#   statistic                 = "Average"
#   threshold                 = "80"
#   alarm_description         = "This metric monitors ec2 cpu utilization"
#   insufficient_data_actions = []
# }


output "master1_access" {
    value = ["ssh ubuntu@${aws_instance.master-c1.public_ip}"]
}

output "master2_access" {
    value = ["ssh ubuntu@${aws_instance.master-c2.public_ip}"]
}

output "app_loadbalancer" {
    value = ["${aws_elb.k8s-app.dns_name}"]
}