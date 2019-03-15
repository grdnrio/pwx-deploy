#############################################################
##
## This app file contains the variables of Kubernetes Installation
## on Packet Cloud
## 
## @year 2019
## @author Joe Gardiner <joe@grdnr.io>
##
#############################################################
### Region
variable "auth_token" {
  description = "Your API token. Get this from the Packet Cloud dashboard"
  default=""
}
variable "project" {
  description = "Your project name"
  default="Portworx"
}
variable "region" {
  description = "The region to deploy the kubernetes clusters"
  default="ams1"
}

variable "worker_count" {
  description = "Number of workers"
  default="3"
}

variable "private_key_path" {
  description = "Path to private SSH key"
  default = ""
}
