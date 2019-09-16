#############################################################
##
## This app file contains the variables of Kubernetes Installation
## on AWS
## 
## @year 2019
## @author Joe Gardiner <joe@grdnr.io>
##
#############################################################
### Region
variable "aws_region" {
  description = "The region to deploy the kubernetes clusters"
  default=""
}

variable "key_name" {
  description = "Key pair name to use for SSH"
  default = ""
}

variable "private_key_path" {
  description = "Path to private SSH key"
  default = ""
}

variable "stork_version" {
  description = "Version of Stork to use"
  default = "latest"
}

variable "storkctl_version" {
  description = "Version of storkctl to use"
  default = "latest"
}

variable "kube_version" {
  description = "Version of storkctl to use"
  default = "1.15.3"
}