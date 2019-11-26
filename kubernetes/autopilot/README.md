# Portworx - AutoPilot on GCP
This is a Terraform script to one Kubernetes cluster, with Portworx, AutoPilot, AutoPilot Rules and a Postgres Benchmark deployment that will quickly consume space on its PV.

## Requirements
- Portworx 2.3 or greater
- Terraform 12.x or greater
- gcloud CLI (tested with SDK 271.x)

## Installed Componenets
- Portworx Volumes
- Prometheus
- Lighthouse
- Grafana with dashboards
- Storkctl
- AutoPilot 1.x

You need to have Terraform installed and your GCP credentials set in your ssh agent or the public/private key referenced in the variables below.

`brew install terraform`

This repo assumes you have created a project in Google Cloud, enabled billing and uploaded your SSH key to the project.

## Instructions
1. Clone the repo

2. Change into the root of the repo and create a file to store your specific variable. Call the file `terraform.tfvars`
Add the following values and change the examples below to match your needs:
```
### GCP Region
gcp_region = "europe-west2"

### GCP Zone
gcp_zone = "europe-west2-c"

## Project Name in Google Cloud
gcp_project = ""

### Existing keypair name
key_name = ""

### SSH User
ssh_user = "ubuntu"

### Private ssh key for keypair path
private_key_path = ""

### Public ssh key for keypair path
public_key_path = ""

### Number of clusters
clusters = ["1"]

### Stork version
stork_version = latest

### Storkctl version
storkctl_version = latest

### Portworx version
portworx_version = 2.3.1

### Kubernetes version
kube_version = 1.15.6
```
Note that the existing keypair name is a stored SSH key in your GCP Project. Make sure it exists in your chosen region.

3. Initialise the repo with the required modules
`terraform init`

4. Run the Terraform plan
`terraform plan`

5. Run the deployment
`terraform apply --auto-approve`

6. Apply the AutoPilot volume resize rule on the master node
`kubectl apply -f /tmp/ap-postgres-rule.yaml`

## Environment
- There is a deployment called 'pgbench' edit this deployment and increase the replicas to '1' to start filling the volumes
- kube config is set on the masters, no sudo required
- storkctl is setup on the masters
- there's a repo of demo app manifests pulled onto each master
