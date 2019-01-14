sudo -i
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
echo deb http://apt.kubernetes.io/ kubernetes-xenial main >/etc/apt/sources.list.d/kubernetes.list
apt update -y
apt install -y docker.io kubeadm
systemctl enable docker kubelet
systemctl restart docker kubelet
kubeadm config images pull &
wait
$IP=ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}'
kubeadm init --apiserver-advertise-address=$IP --pod-network-cidr=10.244.0.0/16
mkdir /root/.kube /home/ubuntu/.kube /tmp/grafanaConfigurations
cp /etc/kubernetes/admin.conf /root/.kube/config
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu.ubuntu /home/ubuntu/.kube
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f 'https://install.portworx.com/2.0?kbver=1.13.1&b=true&m=ens5&d=ens5&c=px-demo-#{c}&stork=true&st=k8s&lh=true'
kubectl apply -f https://docs.portworx.com/samples/k8s/portworx-pxc-operator.yaml
kubectl create secret generic alertmanager-portworx -n kube-system --from-file=<(curl -s https://docs.portworx.com/samples/k8s/portworx-pxc-alertmanager.yaml | sed 's/<.*address>/dummy@dummy.com/;s/<.*password>/dummy/;s/<.*port>/localhost:25/')
while : ; do
kubectl apply -f https://docs.portworx.com/samples/k8s/prometheus/02-service-monitor.yaml
[ $? -eq 0 ] && break
done
kubectl apply -f https://docs.portworx.com/samples/k8s/prometheus/05-alertmanager-service.yaml
kubectl apply -f https://docs.portworx.com/samples/k8s/prometheus/06-portworx-rules.yaml
kubectl apply -f https://docs.portworx.com/samples/k8s/prometheus/07-prometheus.yaml
curl -o /tmp/grafanaConfigurations/Portworx_Volume_template.json -s https://raw.githubusercontent.com/portworx/px-docs/gh-pages/k8s-samples/grafana/dashboards/Portworx_Volume_template.json
curl -o /tmp/grafanaConfigurations/dashboardConfig.yaml -s https://raw.githubusercontent.com/portworx/px-docs/gh-pages/k8s-samples/grafana/config/dashboardConfig.yaml
kubectl create configmap grafana-config --from-file=/tmp/grafanaConfigurations -n kube-system
kubectl apply -f <(curl -s https://docs.portworx.com/samples/k8s/grafana/grafana-deployment.yaml | sed 's/config.yaml/dashboardConfig.yaml/g;/- port: 3000/a\\    nodePort: 30950')
curl -s http://openstorage-stork.s3-website-us-east-1.amazonaws.com/storkctl/2.0.0/linux/storkctl -o /usr/bin/storkctl
chmod +x /usr/bin/storkctl
if [ $(hostname) != master-1 ]; then
while : ; do
    token=$(ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no node-#{c}-1 pxctl cluster token show | cut -f 3 -d " ")
    echo $token | grep -Eq '.{128}'
    [ $? -eq 0 ] && break
    sleep 5
done
storkctl generate clusterpair -n default remotecluster-#{c} | sed '/insert_storage_options_here/c\\    ip: node-#{c}-1\\n    token: '$token >/root/cp.yaml
cat /root/cp.yaml | ssh -oConnectTimeout=1 -oStrictHostKeyChecking=no master-1 kubectl apply -f -