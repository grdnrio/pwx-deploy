provider "packet" {
  auth_token = var.auth_token
}

# Create a project
resource "packet_project" "project" {
  name = var.project
}

resource "packet_device" "master" {
  hostname = "master"
  connection {
    host        = self.access_public_ipv4
    type        = "ssh"
    user        = "root"
    private_key = file(var.private_key_path)
  }
  plan             = "m2.xlarge.x86"
  facilities       = [var.region]
  operating_system = "ubuntu_16_04"
  billing_cycle    = "hourly"
  project_id       = packet_project.project.id
  provisioner "file" {
    source      = var.private_key_path
    destination = "/root/.ssh/id_rsa"
  }
  provisioner "file" {
    source      = "../files/"
    destination = "/tmp"
  }
}

resource "packet_device" "worker" {
  count    = var.worker_count
  hostname = "worker-${count.index + 1}"
  connection {
    host        = self.access_public_ipv4
    type        = "ssh"
    user        = "root"
    private_key = file(var.private_key_path)
  }
  plan             = "m2.xlarge.x86"
  facilities       = [var.region]
  operating_system = "ubuntu_16_04"
  billing_cycle    = "hourly"
  project_id       = packet_project.project.id
  provisioner "file" {
    source      = var.private_key_path
    destination = "/root/.ssh/id_rsa"
  }
}

data "template_file" "hosts" {
  template = file("hosts.tpl")
  depends_on = [
    packet_device.worker,
    packet_device.master,
  ]
  vars = {
    master   = packet_device.master.access_private_ipv4
    worker-1 = packet_device.worker[0].access_private_ipv4
    worker-2 = packet_device.worker[1].access_private_ipv4
    worker-3 = packet_device.worker[2].access_private_ipv4
  }
}

resource "null_resource" "hosts" {
  triggers = {
    template_rendered = data.template_file.hosts.rendered
  }
  connection {
    user        = "root"
    private_key = file(var.private_key_path)
    host        = packet_device.master.access_public_ipv4
  }
  provisioner "file" {
    content     = data.template_file.hosts.rendered
    destination = "/etc/hosts"
  }
}

resource "null_resource" "master" {
  triggers = {
    version = timestamp()
  }
  depends_on = [null_resource.hosts]
  connection {
    user        = "root"
    private_key = file(var.private_key_path)
    host        = packet_device.master.access_public_ipv4
  }
  provisioner "remote-exec" {
    inline = [
      "export LC_ALL=en_US.UTF-8",
      "chmod 600 /root/.ssh/id_rsa",
      "swapoff -a",
      "apt-get update && apt-get install -y git",
      "git clone https://github.com/grdnrio/sa-toolkit.git",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add",
      "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | tee --append /etc/apt/sources.list.d/kubernetes.list",
      "apt-get remove docker docker-engine docker.io containerd runc",
      "apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -",
      "sleep 10",
      "until find /etc/apt/ -name *.list | xargs cat | grep  ^[[:space:]]*deb | grep docker; do add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"; sleep 2; done",
      "wait",
      "until docker; do apt-get update && apt-get install -y docker-ce=18.06.3~ce~3-0~ubuntu; sleep 2; done",
      "apt-get install -y kubeadm",
      "systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "kubeadm config images pull",
      "wait",
      "kubeadm init --apiserver-advertise-address=${packet_device.master.access_private_ipv4} --pod-network-cidr=10.244.0.0/16 --node-name master",
      "kubeadm token create abcdef.1234567890abcdef",
      "mkdir /root/.kube",
      "cp /etc/kubernetes/admin.conf /root/.kube/config",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml",
      "kubectl apply -f https://docs.portworx.com/samples/k8s/portworx-pxc-operator.yaml",
      "kubectl create secret generic alertmanager-portworx --from-file=/tmp/portworx-pxc-alertmanager.yaml -n kube-system",
      "kubectl apply -f 'https://install.portworx.com/2.0?mc=false&kbver=1.13.4&b=true&s=%2Fdev%2Fnvme0n1&j=auto&c=px-demo&stork=true&lh=true&mon=true&st=k8s'",
      "kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml",
      "snap install helm --classic",
      "kubectl apply -f /tmp/tiller-rbac.yaml",
      ". ~/.profile",
      "helm init --service-account tiller",
      "curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/2.0.0/linux/storkctl -o /usr/bin/storkctl && chmod +x /usr/bin/storkctl",
    ]
  }
}

resource "null_resource" "worker" {
  triggers = {
    version = timestamp()
  }
  count      = length(packet_device.worker)
  depends_on = [null_resource.master]
  connection {
    user        = "root"
    private_key = file(var.private_key_path)
    host        = element(packet_device.worker.*.access_public_ipv4, count.index)
  }
  provisioner "remote-exec" {
    inline = [
      "export LC_ALL=en_US.UTF-8",
      "chmod 600 /root/.ssh/id_rsa",
      "swapoff -a",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add",
      "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | tee --append /etc/apt/sources.list.d/kubernetes.list",
      "apt-get remove docker docker-engine docker.io containerd runc",
      "apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -",
      "sleep 10",
      "until find /etc/apt/ -name *.list | xargs cat | grep  ^[[:space:]]*deb | grep docker; do add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"; sleep 2; done",
      "wait",
      "until docker; do apt-get update && apt-get install -y docker-ce=18.06.3~ce~3-0~ubuntu; sleep 2; done",
      "wait",
      "apt-get install -y kubeadm",
      "systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "kubeadm config images pull",
      "kubeadm join ${packet_device.master.access_private_ipv4}:6443 --token abcdef.1234567890abcdef --discovery-token-unsafe-skip-ca-verification",
    ]
  }
}

output "master_access" {
  value = "ssh root@${packet_device.master.access_public_ipv4}"
}

