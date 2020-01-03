# Portworx - AutoPilot & PX-Backup on GCP
This is a Terraform script to one Kubernetes cluster, with Portworx, AutoPilot, AutoPilot Rules and a Postgres Benchmark deployment that will quickly consume space on its PV.

## Requirements
- Portworx 2.3 or greater
- Terraform 12.x or greater
- gcloud CLI (tested with SDK 271.x)

## Installed Components
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

2. Create a GCP project, make a note of the name. You will need to add it to the variables file below.

3. Generate a gcp credentials json file and save locally. You will need to add it to the variables file below.

4. Change into the root of the repo and create a file to store your specific variable. Call the file `variables.tf`
Add the following values and change the examples below to match your needs:
```
variable "gcp_region" {
  description = "The region to deploy the kubernetes clusters"
  default     = "europe-west2"
}
variable "gcp_zone" {
  description = "The zone to deploy the kubernetes clusters"
  default     = "europe-west2-c"
}

variable "gcp_project" {
  description = "The project to deploy the kubernetes clusters"
  default     = ""
}

variable "gcp_credentials" {
  description = "The project credentials file"
  default     = ""
}

variable "key_name" {
  description = "Key pair name to use for SSH"
  default     = ""
}

variable "ssh_user" {
  description = "ssh user to connect to instance"
  default     = "ubuntu"
}

variable "private_key_path" {
  description = "Path to private SSH key"
  default     = ""
}

variable "public_key_path" {
  description = "Path to public SSH key"
  default     = ""
}

variable "cidr_range" {
  description = "CIDR Range to use"
  default     = "10.127.0.0/20"
}

variable "stork_version" {
  description = "Version of Stork to use"
  default     = "latest"
}

variable "storkctl_version" {
  description = "Version of storkctl to use"
  default     = "latest"
}

variable "kube_version" {
  description = "Version of kubernetes to use"
  default     = "1.15.6"
}

variable "portworx_version" {
  description = "Version of portworx to use"
  default     = "2.3.1"
}

```
Note that the existing keypair name is a stored SSH key in your GCP Project. Make sure it exists in your chosen region.

3. Initialise the repo with the required modules
`terraform init`

4. Run the Terraform plan
`terraform plan`

5. Run the deployment
`terraform apply --auto-approve`

## Environment
- kube config is set on the masters, no sudo required
- storkctl is setup on the masters
- there's a repo of demo app manifests pulled onto each master

## AutoPilot Demo
There are options to use postgres or cockroachdb as a demo. Using both will cause slowdowns.

- There is a postgres benchmark deployment called 'pgbench', edit this deployment and increase the replicas to '1' to start filling the volumes
- There are deployment options for CockroachDB, the 1 node instance is running by default
    - `/tmp/cockroach-db-1node.yaml` - deploys 1 instance of CockroachDB with 3 PX replicas
    - `/tmp/cockroach-db-3node.yaml` - deploys 3 instance of CockroachDB with their own volumes, 1 PX replica each
- There are two AutoPilot rules applied to handle growing the PVCs
    - `/tmp/ap-cockroach-rule.yaml` - deploys an AutoPilot rule to increase the volume size by 30% when the utilisation hits 50%
    - `/tmp/ap-postgres-rule` - deploys an AutoPilot rule to increase the volume size by 50% when the utilisation hits 50%
- Two scripts are provided
    - `/tmp/cockroach-loadgen.sh` - starts filling the cockroachdb storage
    - `watch-autopilot.sh` - print AutoPilot events to the terminal
- There is a Grafana dashboard, this is a stripped down version of the PX Volume Dashboard to improve performance
    - `/tmp/ap-dashboard.json`

## PX-Backup Demo
This will deploy a minio s3 store into a 'minio' namespace and a petclinic sample app into a 'petclinic' namespace

- Deploy minio 
    - `kubectl apply -f /tmp/px-backup/minio-deployment.yaml`
- Deploy petclinic sample app
    - `kubectl apply -f /tmp/px-backup/petclinic-deployment.yaml`
- Log onto minio using minio/minio123 and create a bucket called 'portworx'
- Edit `/tmp/px-backup/backupLocation.yaml` and update the endpoint to your minio instance
- Apply the backup location 
    -`kubectl apply -f /tmp/px-backup/backupLocation.yaml`
- Create a backup of the petclinic namespace
    - `kubectl apply -f /tmp/px-backup/applicationBackup.yaml`
- Check the backup was successful
    - `kubectl describe applicationbackups -n petclinic`
- Delete the petclinic namespace
    - `kubectl delete ns petclinic`
- Recreate the namespace
    - `kubectl create ns petclinic`
- Apply the backup location
    - `kubectl apply -f /tmp/px-backup/backupLocation.yaml`
- Watch for the backup to be created
    - `watch kubectl get applicationbackups -n petclinic`
- Make a note of the backup name (it will be appended with a timestamp)
- Edit `/tmp/px-backup/applicationRestore.yaml` and add in the backupName
- Apply the application restore
    - `kubectl apply -f /tmp/px-backup/applicationRestore.yaml`
- Watch the data and resources get re-created
    - `watch kubectl get all -n petclinic`