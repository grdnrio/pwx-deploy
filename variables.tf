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

variable "clusters" {
  description = "The number of Kubernetes clusters to deploy"
  default="2"
}

variable "key_name" {
  description = "Key pair name to use for SSH"
  default=""
}
