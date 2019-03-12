# Portworx - Kubernetes Deploy
This is a Terraform script to one or more Kubernetes clussters, each with a running Portworx cluster on AWS. It pre-configures the following:

- Portworx latest version
- Prometheus
- Lighthouse
- Grafana with dashboard
- Storkctl configured with cluster 1 as the source and cluster 2 as the destination (if multiple cluster)

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

### Number of clusters
clusters = ["1"]
```
Note that the existing keypair name is a stored SSH keypair on AWS. Make sure it exists in your chosen region.

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
