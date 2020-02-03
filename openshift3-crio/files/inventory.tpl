[OSEv3:children]
masters
etcd
nodes
[OSEv3:vars]
ansible_ssh_user=centos
ansible_sudo=true
ansible_become=true
deployment_type=origin
os_sdn_network_plugin_name='redhat/openshift-ovs-multitenant'
openshift_install_examples=true
openshift_use_crio=True
openshift_use_crio_only=True
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider'}]
openshift_master_htpasswd_users={'admin' : '$apr1$zTCG/myL$mj1ZMOSkYg7a9NLZK9Tk9.'}
openshift_master_default_subdomain=apps.${app_sub_domain}
openshift_master_cluster_public_hostname=${master_public_ip}
openshift_master_cluster_hostname=${master_public_ip}
openshift_disable_check=disk_availability,docker_storage,memory_availability
openshift_hosted_router_selector='node-role.kubernetes.io/infra=true'
openshift_enable_service_catalog=false
[masters]
master
[etcd]
master
[nodes]
master openshift_node_group_name="node-config-master-infra-crio" openshift_schedulable=true
worker-1 openshift_node_group_name="node-config-compute-crio"
worker-2 openshift_node_group_name="node-config-compute-crio"
worker-3 openshift_node_group_name="node-config-compute-crio"
