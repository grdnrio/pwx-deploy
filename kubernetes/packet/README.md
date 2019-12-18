# Portworx - Kubernetes Deploy on PACKET CLOUD
This is a Terraform script to one or more Kubernetes clusters, each with a running Portworx cluster on Packet Cloud bare metal servers. It pre-configures the following:

- Portworx latest version
- Prometheus
- Lighthouse
- Grafana with dashboard

You need to have Terraform >= 0.12 installed and and account created on Packet Cloud

`brew install terraform`

## Instructions
1. Clone the repo

2. Change into the root of the repo and create a file to store your specific variable. Call the file `terraform.tfvars`
Add the following values and change the examples below to match your needs:
```
auth_token = "<your org auth token>"
project = "tf-test"
region = "ams1"
worker_count = "3"
private_key_path = "<path to your private key>"
```
Note that the existing keypair name is a stored SSH keypair on Packet Cloud. Make sure it exists in your chosen org.

3. Initialise the repo with the required modules
`terraform init`

4. Run the Terraform plan
`terraform plan`

5. Run the deployment
`terraform apply -auto-approve`

## Environment
- you can ssh between machines using the hosts in the hosts file `/etc/hosts`.
- kube config is set on the masters, no sudo required
- there's a repo of manifests pulled onto each master
