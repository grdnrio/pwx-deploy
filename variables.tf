#############################################################
##
## This app file contains the variables of Kubernetes Installation
## on AWS
## 
## @year 2019
## @author Joe Gardiner <joe@grdnr.io>
##
#############################################################
### Provider
variable "aws_region" {
  description = "The region to deploy the kubernetes clusters"
  default="eu-west-2"
}

variable "key_name" {
  description = "Key pair name to use for SSH"
  default = "jgardiner"
}

variable "private_key_path" {
  description = "Path to private SSH key"
  default = "/Users/joe/.ssh/id_rsa"
}