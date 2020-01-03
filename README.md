# Portworx Demo / Testing Deployment
This repo provides a number of Terraform templates for deploying various container schedulers with Portworx.  Check each scheduler directory for specific requirements. All deployments require the following.

## Pre-requisites
You need the following packages on your workstation
- Terraform >= 0.12
- aws-cli
- Ansible

Make sure you have your AWS credentials set and an SSH key-pair in the required AWS regions.

## Demos
These are the following demo environments deployable from this repo.
1. 2 x Kubernetes with cluster pairing established - [kubernetes](kubernetes) (you can confiure to deploy one cluster - check the Readme)
This envionrment is suitable for a standard Kuberntes demo.
2. Single OpenShift 3.11 with Portworx pre-installed and the dashboard / service catalogue [OpenShift](openshift)
3. Single Rancger cluster - Portworx is not pre-installed. [Rancher](rancher)
4. Single Swarm cluster with Portworx pre-installed [Docker Swarm](swarm)
5. Portworx Metro - 2 K8s clusters with a single Portworx stretch [PX Metro](kubernetes/px-metro)
6. Autopilot - 1 K8s cluster deployed on GCP with AutoPilot, example rules and postgres benchmark [AutoPilot](kubernetes/autopilot)
