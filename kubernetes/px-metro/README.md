# Portworx Metro - Deploy
This is a Terraform script to deploy a px-metro demo. It deploys two separate Kubernetes clusters with a single stretch Portworx using an external etcd. It pre-configures the following:

- Portworx latest version
- Cluster pairing
- Resource syncing
- Prepared cluster down scripts

You need to have Terraform installed and your AWS credentials set in `~/.aws/credentials`

`brew install terraform`

## Instructions
1. Clone the repo

2. Change into the root of the repo and create a file to store your specific variable. Call the file `terraform.tfvars`
Add the following values and change the examples below to match your needs:
```
### Region
aws_region = "eu-west-2"

### Existing keypair name
key_name = "jgardiner"

### Private ssh key for keypair path
private_key_path = "/Users/joe/.ssh/id_rsa"

### License key for PX Enterprise
license_1 = "123456"

### License key for PX Enterprise DR
license_2 = "123456"
```
^^ Use provided SA license keys here.

Note that the existing keypair name is a stored SSH keypair on AWS. Make sure it exists in your chosen region.

3. Initialise the repo with the required modules
`terraform init`

4. Run the Terraform plan
`terraform plan`

5. Run the deployment
`terraform apply --auto-approve`

## Environment
- you can ssh between machines using the hosts in the hosts file `/etc/hosts`.
- kube config is set on the masters, no sudo required
- storkctl is setup on the masters
- there's a repo of demo app manifests pulled onto each master

## Demo
To mark cluster 1 as down take a look at the manifest in /tmp on the master. Apply this to trigger the failover to the secondary cluster. You can use the ELB public DNS as provided in the Terraform output to demonstrate that this failover occurs.