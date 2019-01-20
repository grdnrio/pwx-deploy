# pwx-tf-deploy
This is a Terraform script to deploy two Kubernetes clusters, each with a running Portworx cluster on AWS. It pre-configures the following:

- Portworx latest version
- Prometheus in both clusters
- Lighthouse in both clusters
- Grafana with dashboards in both clusters
- Storkctl configured with cluster 1 as the source and cluster 2 as the destination

You need to have Terraform installed with your AWS credentials set in `~/.aws/credentials`

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
```
Note that the existing keypair name is a stored SSH keypair on AWS. MAke sure it exists in your chosen region.

3. Initialise the repo with the required modules
`terraform init`

4. Run the Terraform plan
`terraform plan`

5. Run the deployment
`terraform apply -auto-approve`

## Environment
- you can ssh between machines using the hosts in the hosts file `/etc/hosts`.
- kube config is set on the masters, no sudo required
- storkctl is setup on the masters
- there's a repo of manifests pulled onto each master

## Issues
- sometimes one of the workers fails to find the `docker.io` package. Just destroy and redeploy.