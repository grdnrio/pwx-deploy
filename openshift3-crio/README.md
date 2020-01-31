# OpenShift 3.X w/ CRI-O Deploy
This is a Terraform script to deploy OpenShift 3.11 with the Container Runtime being CRI-O (instead of Docker).  Portworx is not installed automatically

You need to have Terraform >= 0.12 installed and your AWS credentials set in `~/.aws/credentials`

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

### where a wildcard entry should already exists (e.g. *.apps.whateverdomain.com) that you would then point to the master node
app_sub_domain = "whateverdomain.com"
```
Note that the existing keypair name is a stored SSH keypair on AWS. Make sure it exists in your chosen region.

3. Initialise the repo with the required modules
`terraform init`

4. Run the Terraform plan
`terraform plan`

5. Run the deployment
`terraform apply --auto-approve`

## Environment
- you can ssh between machines using the hosts in the hosts file `/etc/hosts`.
- check the Terraform output for dashboard access
- remember to use oc instead of kubectl!
- kube config is set on the masters, no sudo required
- there's a repo of demo app manifests pulled onto the master
