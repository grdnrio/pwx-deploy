sudo -i
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
echo deb http://apt.kubernetes.io/ kubernetes-xenial main >/etc/apt/sources.list.d/kubernetes.list
apt update -y
apt install -y docker.io kubeadm
systemctl enable docker kubelet
systemctl restart docker kubelet
kubeadm config images pull &
(docker pull portworx/oci-monitor:2.0.1 ; docker pull openstorage/stork:2.0.1 ; docker pull portworx/px-enterprise:2.0.1) &
while : ; do
    command=$(ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no master-1 kubeadm token create --print-join-command)
    [ $? -eq 0 ] && break
    sleep 5
done
wait %1
eval $command