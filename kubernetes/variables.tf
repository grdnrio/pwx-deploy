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
  default="eu-west-2"
}

variable "key_name" {
  description = "Key pair name to use for SSH"
  default = "dwelc"
}

variable "private_key_path" {
  description = "Path to private SSH key"
  default = "~/Documents/ssh-sessions/aws/keys/dwelc.pem"
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
  description = "Version of kubernetes to use"
  default = "1.15.3"
}

variable "portworx_version" {
  description = "Version of kubernetes to use"
  default = "2.1.2"
}