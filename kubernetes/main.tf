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
  version = "~> 2.0"
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
  source = "../modules/network"
}

resource "aws_instance" "master" {
  
  tags = {
    Name = "master-c${count.index + 1}"
  }
  
  count = "${length(var.clusters)}"

  connection {
    # The default username for our AMI
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${self.public_ip}"
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
  vpc_security_group_ids = ["${module.aws_networking.security_group}"]
  subnet_id = "${module.aws_networking.subnet}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "20"
  }

  provisioner "file" {
    source      = "files/"
    destination = "/tmp"
  }

    provisioner "file" {
    source      = "../apps/"
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
      "kubectl create secret generic alertmanager-portworx --from-file=/tmp/portworx-pxc-alertmanager.yaml -n kube-system",
      "kubectl apply -f 'https://install.portworx.com/2.0.2?mc=false&kbver=1.13.3&b=true&c=px-demo-${count.index + 1}&stork=true&lh=true&mon=true&st=k8s'",
      "kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml",
      
      # Stork binary installation
      "sudo curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/2.0.0/linux/storkctl -o /usr/bin/storkctl && sudo chmod +x /usr/bin/storkctl",

    ]
  }
}

resource "aws_instance" "worker" {
  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${self.public_ip}"
  }
  depends_on = ["aws_instance.master"]
  count = "${length(var.clusters) * length(var.workers)}"
  instance_type = "t2.medium"
  tags = {
    Name = "worker-c${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
  }
  private_ip = "10.0.1.${var.clusters[count.index % length(var.clusters)]}${var.workers[count.index % length(var.workers)]}"
  ami = "${data.aws_ami.default.id}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${module.aws_networking.security_group}"]
  subnet_id = "${module.aws_networking.subnet}"
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
      "sudo docker pull portworx/oci-monitor:2.0.1 ; sudo docker pull openstorage/stork:2.0.1 ; sudo docker pull portworx/px-enterprise:2.0.1",
      "sudo kubeadm join 10.0.1.${var.clusters[count.index % length(var.clusters)]}0:6443 --token ${var.join_token} --discovery-token-unsafe-skip-ca-verification --node-name ${self.tags.Name}"
    ]
  }
}

resource "null_resource" "appdeploy" {

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.0.public_ip}"
  }
  triggers = {
    build_number = "${timestamp()}"
  }

  depends_on = ["aws_instance.worker", "aws_instance.master"]

  provisioner "remote-exec" {
    inline = [
      # Deploy demo app
      "kubectl apply -f /tmp/apps/petclinic-db.yaml",
      "kubectl apply -f /tmp/apps/petclinic-deployment.yaml",
      "kubectl apply -f /tmp/apps/postgres-deployment.yaml",
      "kubectl apply -f /tmp/apps/mongo-deployment.yaml",
      "kubectl apply -f /tmp/apps/mysql-deployment.yaml",
      "kubectl apply -f /tmp/apps/redis-deployment.yaml",
      "kubectl apply -f /tmp/apps/wordpress-db.yaml",
      "kubectl apply -f /tmp/apps/wordpress-deployment.yaml"
      #"kubectl apply -f /tmp/apps/jenkins-deployment.yaml"
      #"kubectl apply -f /tmp/apps/minio-deployment.yaml"
    ] 
  }
}

resource "null_resource" "storkctl" {

  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
    host = "${aws_instance.master.0.public_ip}"
  }
  triggers = {
    multi_master = "${ length(var.clusters) > 1 }"
  }

  depends_on = ["null_resource.appdeploy"]

  provisioner "remote-exec" {
    inline = [
<<EOF
if ssh -oStrictHostKeyChecking=no worker-c2-1 bash -c 'kubectl' ; then
  while : ; do
    token=$(ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no worker-c2-1 pxctl cluster token show | cut -f 3 -d " ")
    echo $token | grep -Eq '.{128}'
    [ $? -eq 0 ] && break
    sleep 5
  done
  ssh -oStrictHostKeyChecking=no master-c2 storkctl generate clusterpair -n default remotecluster | sed '/insert_storage_options_here/c\    ip: worker-c2-1\n    token: '$token >/home/ubuntu/cp.yaml
  kubectl apply -f /home/ubuntu/cp.yaml
else
  echo "Nothing to do. Single cluster deployment"
fi
EOF
    ] 
  }
}

output "master_access" {
    value = ["ssh ubuntu@${aws_instance.master.0.public_ip}"]
}



output "master_petclinic" {
    value = ["http://${aws_instance.master.0.public_ip}:30333"]
}