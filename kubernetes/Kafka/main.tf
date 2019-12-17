#############################################################
##
## This app file contains the bootstrap of Kubernetes Installation
## on GCP
## 
## @year 2019
## @author Dan Welch <daniel.welch@outlook.com>
##
#############################################################

# Specify the provider and access details
provider "google" {
  credentials = file(var.gcp_credentials)
  project     = var.gcp_project
  region      = var.gcp_region
  zone        = var.gcp_zone
}

variable "clusters" {
  type = list
  default = ["1"]
}

variable "workers" {
  type = list
  default = ["1", "2", "3"]
}

variable "join_token" {
  type= string
  default = "abcdef.1234567890abcdef"
}


resource google_compute_network "default" {
  name = "terraform-network"
  auto_create_subnetworks = "false"
}

resource google_compute_subnetwork "default" {
  name                      = "terraform-sub-network"
  ip_cidr_range             = var.cidr_range
  network                   = google_compute_network.default.self_link
  region                    = var.gcp_region
  private_ip_google_access  = true
}

resource "google_compute_firewall" "allow-all" {
  name          = "allow-all"
  network       = google_compute_network.default.name
  allow {
      protocol  = "tcp"
  }
  allow {
      protocol  = "udp"
    }
}

resource "google_compute_disk" "data" {
  count = length(var.clusters) * length(var.workers)
  zone  = var.gcp_zone
  name  = "workerdisk-c${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
  size  = "30"
  type  = "pd-ssd"
}

resource "google_compute_disk" "data2" {
  count = length(var.clusters) * length(var.workers)
  zone  = var.gcp_zone
  name  = "workerdisk2-c${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
  size  = "30"
  type  = "pd-standard"
}

resource "google_compute_instance" "master" {

  name          = "master-c${count.index + 1}"
  machine_type  = "n1-standard-4"
  count         = length(var.clusters)
  tags          = ["master"]

  connection {
    # SSH Configuration
    user          = "ubuntu"
    private_key   = file(var.private_key_path)
    host          = self.network_interface[0].access_config[0].nat_ip
  }
  
  boot_disk {
    auto_delete = "true"
    initialize_params {
      image     = "ubuntu-os-cloud/ubuntu-1604-lts"
      size      = "20"
      type      = "pd-ssd"
     }  
  }

  network_interface {
    network       = google_compute_network.default.name
    subnetwork    = google_compute_subnetwork.default.name
    access_config {
      //Ephemeral IP
    }
  }

  metadata = {
    ssh-keys    = "${var.ssh_user}:${file(var.public_key_path)}"
  }

  provisioner "file" {
    source      = "files/"
    destination = "/tmp"
}
  provisioner "file" {
    source      = "../../apps/"
    destination = "/tmp/apps"
}


   provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo chmod 600 /home/ubuntu/.ssh/id_rsa",
      "sudo cat /tmp/hosts | sudo tee --append /etc/hosts",
      "git clone https://github.com/grdnrio/sa-toolkit.git",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add",
      "sudo echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee --append /etc/apt/sources.list.d/kubernetes.list",
      
      # Install Docker CE
      "sudo apt-get remove docker docker-engine docker.io containerd runc",
      ## Set up the repository:
      ### Install packages to allow apt to use a repository over HTTPS
      "sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common",
      ### Add Docker’s official GPG key
      "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      ### Add Docker apt repository.
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      ## Install Docker CE.
      "until docker; do sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io; sleep 2; done",
      # Setup daemon.
      "sudo cp /tmp/daemon.json /etc/docker/daemon.json ",
      "sudo mkdir -p /etc/systemd/system/docker.service.d",
      # Restart docker.
      "sudo systemctl daemon-reload",
      "sudo systemctl restart docker",

      "sudo apt-get install -y kubeadm=${var.kube_version}-00 kubelet=${var.kube_version}-00 kubectl=${var.kube_version}-00",
      "sudo systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "sudo kubeadm config images pull",
      "wait",
      "sudo kubeadm init --apiserver-advertise-address=${self.network_interface[0].network_ip} --pod-network-cidr=10.244.0.0/16 --node-name ${self.name}",
      "sudo kubeadm token create ${var.join_token}",
      "sudo mkdir /root/.kube /home/ubuntu/.kube /tmp/grafanaConfigurations",
      "sudo cp /etc/kubernetes/admin.conf /root/.kube/config && sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config",
      "sudo chown -R ubuntu.ubuntu /home/ubuntu/.kube",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml",
      "kubectl apply -f https://2.3.docs.portworx.com/samples/k8s/grafana/prometheus-operator.yaml"
    ]
}
}

resource "google_compute_instance" "worker" {

  name          = "worker-c${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
  machine_type  = "n1-standard-4"
  count         = length(var.clusters) * length(var.workers)
  tags          = ["worker"]
  depends_on    = [google_compute_instance.master]

  connection {
    # SSH Configuration
    user          = "ubuntu"
    private_key   = file(var.private_key_path)
    host          = self.network_interface[0].access_config[0].nat_ip
  }
  
  boot_disk {
    auto_delete = "true"
    initialize_params {
      image     = "ubuntu-os-cloud/ubuntu-1604-lts"
      size      = "20"
      type      = "pd-ssd"
     }  
  }

  attached_disk {
    source      = "workerdisk-c${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
    device_name = "sdd"
    mode        = "READ_WRITE"
  }

  attached_disk {
    source      = "workerdisk2-c${var.clusters[count.index % length(var.clusters)]}-${var.workers[count.index % length(var.workers)]}"
    device_name = "sdf"
    mode        = "READ_WRITE"
  }

  network_interface {
    network       = google_compute_network.default.name
    subnetwork    = google_compute_subnetwork.default.name
    access_config {
      //Ephemeral IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.public_key_path)}"
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
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo chmod 600 /home/ubuntu/.ssh/id_rsa",
      "sudo cat /tmp/hosts | sudo tee --append /etc/hosts",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add",
      "sudo echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee --append /etc/apt/sources.list.d/kubernetes.list",
      
       # Install Docker CE
      "sudo apt-get remove docker docker-engine docker.io containerd runc",
      ## Set up the repository:
      ### Install packages to allow apt to use a repository over HTTPS
      "sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common",
      ### Add Docker’s official GPG key
      "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      ### Add Docker apt repository.
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      ## Install Docker CE.
      "until docker; do sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io; sleep 2; done",
      # Setup daemon.
      "sudo cp /tmp/daemon.json /etc/docker/daemon.json ",
      "sudo mkdir -p /etc/systemd/system/docker.service.d",
      # Restart docker.
      "sudo systemctl daemon-reload",
      "sudo systemctl restart docker",

      "sudo apt-get install -y kubeadm=${var.kube_version}-00 kubelet=${var.kube_version}-00 kubectl=${var.kube_version}-00",
      "sudo systemctl enable docker kubelet && sudo systemctl restart docker kubelet",
      "sudo kubeadm config images pull",
      "sudo docker pull portworx/oci-monitor:${var.portworx_version} ; sudo docker pull openstorage/stork:${var.stork_version}; sudo docker pull portworx/px-enterprise:${var.portworx_version}",
      "sudo kubeadm join ${google_compute_instance.master[0].network_interface[0].network_ip}:6443 --token ${var.join_token} --discovery-token-unsafe-skip-ca-verification --node-name ${self.name}"
    ]
}
}


resource "null_resource" "portworx_setup" {

  connection {
    user          = "ubuntu"
    private_key   = file(var.private_key_path)
    host          = google_compute_instance.master.0.network_interface[0].access_config[0].nat_ip
  }
  triggers = {
    build_number  = "${timestamp()}"
  }

  depends_on      = [google_compute_instance.master, google_compute_instance.worker]


  provisioner "remote-exec" {
    inline = [
      "sleep 60",
      "kubectl apply -f 'https://install.portworx.com/${var.portworx_version}?mc=false&kbver=${var.kube_version}&b=true&c=px-demo-1&stork=true&lh=true&mon=true&st=k8s'",
      "kubectl apply -f /tmp/ap-configmap.yaml",
      "kubectl apply -f /tmp/ap-install.yaml",
      "sleep 30",
      # Stork binary installation
      "sudo curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/${var.storkctl_version}/linux/storkctl -o /usr/bin/storkctl && sudo chmod +x /usr/bin/storkctl"
    ] 
  }
}

resource "null_resource" "label_pools" {

  connection {
    user          = "ubuntu"
    private_key   = file(var.private_key_path)
    host          = google_compute_instance.worker.0.network_interface[0].access_config[0].nat_ip
  }
  triggers = {
    build_number  = "${timestamp()}"
  }

  depends_on      = [google_compute_instance.master, google_compute_instance.worker]


  provisioner "remote-exec" {
    inline = [
      "pxctl service pool update 0 --labels storage=kafka",
      "pxctl service pool update 1 --labels storage=zookeeper"
     ] 
  }
}

resource "null_resource" "label_pools" {

  connection {
    user          = "ubuntu"
    private_key   = file(var.private_key_path)
    host          = google_compute_instance.worker.1.network_interface[0].access_config[0].nat_ip
  }
  triggers = {
    build_number  = "${timestamp()}"
  }

  depends_on      = [google_compute_instance.master, google_compute_instance.worker]


  provisioner "remote-exec" {
    inline = [
      "pxctl service pool update 0 --labels storage=kafka",
      "pxctl service pool update 1 --labels storage=zookeeper"
     ] 
  }
}

resource "null_resource" "label_pools" {

  connection {
    user          = "ubuntu"
    private_key   = file(var.private_key_path)
    host          = google_compute_instance.worker.2.network_interface[0].access_config[0].nat_ip
  }
  triggers = {
    build_number  = "${timestamp()}"
  }

  depends_on      = [google_compute_instance.master, google_compute_instance.worker]


  provisioner "remote-exec" {
    inline = [
      "pxctl service pool update 0 --labels storage=kafka",
      "pxctl service pool update 1 --labels storage=zookeeper"
     ] 
  }
}

resource "null_resource" "install_kafka" {

  connection {
    user          = "ubuntu"
    private_key   = file(var.private_key_path)
    host          = google_compute_instance.worker.0.network_interface[0].access_config[0].nat_ip
  }
  triggers = {
    build_number  = "${timestamp()}"
  }

  depends_on      = [google_compute_instance.master, google_compute_instance.worker]


  provisioner "remote-exec" {
    inline = [
      "kubectl create namespace kz",
      "wget https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.14.0/strimzi-0.14.0.zip",
      "sudo apt-get install -y unzip && unzip strimzi-0.14.0.zip",
      "cd /strimzi && sed -i 's/namespace: .*/namespace: kz/' install/cluster-operator/*RoleBinding*.yaml",
      
     ] 
  }
} 

output "master_access" {
    value = ["ssh ubuntu@${google_compute_instance.master.0.network_interface[0].access_config[0].nat_ip}"]
}

