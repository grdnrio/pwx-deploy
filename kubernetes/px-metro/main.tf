#############################################################
##
## This app file contains the bootstrap of Kubernetes Installation
## on AWS with px-metro configured
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

module "aws_networking" {
  source = "../../modules/network"
}


resource "aws_instance" "etcd" {
  
  tags = {
    Name = "etcd"
  }

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  associate_public_ip_address = true
  private_ip = "10.0.1.30"

  instance_type = "t2.medium"
  ami = "${data.aws_ami.default.id}"
  key_name = "${var.key_name}"

  vpc_security_group_ids = ["${module.aws_networking.security_group}"]
  subnet_id = "${module.aws_networking.subnet}"

  root_block_device = {
    volume_type = "gp2"
    volume_size = "20"
  }

  provisioner "file" {
    source      = "../files/"
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

resource "aws_instance" "master" {
  tags = {
    Name = "master-c${count.index + 1}"
  }

  tags = {
    Cluster = "${count.index + 1}"
  }
  
  count = "${length(var.clusters)}"

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  associate_public_ip_address = true
  private_ip = "10.0.1.${count.index + 1}0"

  instance_type = "t2.medium"
  ami = "${data.aws_ami.default.id}"

  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${module.aws_networking.security_group}"]
  subnet_id = "${module.aws_networking.subnet}"

  root_block_device = {
    volume_type = "gp2"
    volume_size = "20"
  }

  provisioner "file" {
    source      = "../files/"
    destination = "/tmp"
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
      "kubectl apply -f 'https://install.portworx.com/2.1?mc=false&kbver=1.13.3&k=etcd%3Ahttp%3A%2F%2F10.0.1.30%3A2379&c=px-demo&stork=true&st=k8s'",
      "kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml",
      "sleep 10",
      "sudo apt-get update && sudo apt-get install -y jq && hash -r",
      "sudo bash /tmp/patch.sh cluster-${count.index+1}",
      # Stork binary installation
      "sudo curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/latest/linux/storkctl -o /usr/bin/storkctl && sudo chmod +x /usr/bin/storkctl",

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
    Name = "worker-c${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
  }
  tags = {
    Cluster = "${var.clusters[count.index % length(var.clusters)]}"
  }
  private_ip = "10.0.1.${var.clusters[count.index % length(var.clusters)]}${var.workers[count.index % length(var.workers)]}"
  ami = "${data.aws_ami.default.id}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${module.aws_networking.security_group}"]
  subnet_id = "${module.aws_networking.subnet}"
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
    source      = "../files/hosts"
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
      "sudo kubeadm join 10.0.1.${var.clusters[count.index % length(var.clusters)]}0:6443 --token ${var.join_token} --discovery-token-unsafe-skip-ca-verification --node-name ${self.tags.Name}"
    ]
  }
}

resource "aws_resourcegroups_group" "cluster-1" {
  name        = "cluster1"

  resource_query {
    query = <<JSON
{
  "ResourceTypeFilters": [
    "AWS::EC2::Instance"
  ],
  "TagFilters": [
    {
      "Key": "Cluster",
      "Values": ["1"]
    }
  ]
}
JSON
  }
}

resource "aws_resourcegroups_group" "cluster-2" {
  name        = "cluster2"

  resource_query {
    query = <<JSON
{
  "ResourceTypeFilters": [
    "AWS::EC2::Instance"
  ],
  "TagFilters": [
    {
      "Key": "Cluster",
      "Values": ["2"]
    }
  ]
}
JSON
  }
}

resource "aws_elb" "k8s-app" {
  name = "px-metro-demo"
  subnets = ["${module.aws_networking.subnet}"]
  security_groups = ["${module.aws_networking.security_group}"]
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

  instances                   = ["${aws_instance.worker.*.id}", "${aws_instance.master.*.id}"]

  tags = {
    Name = "px-metro-demo-lb"
  }
}


resource "null_resource" "storkctl" {

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.0.public_ip}"
  }
  triggers {
    multi_master = "${ length(var.clusters) > 1 }"
  }

  depends_on = ["aws_instance.master", "aws_instance.worker"]

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
    host = "${aws_instance.master.0.public_ip}"
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


resource "aws_cloudwatch_event_rule" "cluster1-delete" {
  name        = "cluster1-delete"
  description = "Capture the master in cluster1 being terminated"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.ec2"
  ],
  "detail-type": [
    "EC2 Instance State-change Notification"
  ],
  "detail": {
    "state": [
      "shutting-down",
      "stopping"
    ],
    "instance-id": [
      "${aws_instance.master.0.id}"
    ]
  }
}
PATTERN
}


output "master1_access" {
    value = ["ssh ubuntu@${aws_instance.master.0.public_ip}"]
}

output "app_loadbalancer" {
    value = ["${aws_elb.k8s-app.dns_name}"]
}