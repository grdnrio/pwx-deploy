
# Create an OSEv3 group that contains the masters, nodes, and etcd groups
[OSEv3:children]
masters
nodes
etcd

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
# SSH user, this user should allow ssh based auth without requiring a password
ansible_ssh_user=centos

# If ansible_ssh_user is not root, ansible_become must be set to true
ansible_become=true

openshift_deployment_type=origin

# uncomment the following to enable htpasswd authentication; defaults to AllowAllPasswordIdentityProvider
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider'}]

# host group for masters
[masters]
master

# host group for etcd
[etcd]
master

# host group for nodes, includes region info
[nodes]
master openshift_node_group_name='node-config-master'
worker-1 openshift_node_group_name='node-config-compute'
worker-2 openshift_node_group_name='node-config-compute'
worker-3 openshift_node_group_name='node-config-compute'