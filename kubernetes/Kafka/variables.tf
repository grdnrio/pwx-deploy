#############################################################
##
## This app file contains the variables of Kubernetes Installation
## on AWS
## 
## @year 2019
## @author Dan Welch
##
#############################################################
### Region
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
  default     = "premium-bearing-259414"
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
  default     = "/Users/dan/.ssh/dw-gcp-key"
}

variable "public_key_path" {
  description = "Path to public SSH key"
  default     = "/Users/dan/.ssh/dw-gcp-key.pub"
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
  description = "Version of kubernetes to use"
  default     = "2.3.1"
}
