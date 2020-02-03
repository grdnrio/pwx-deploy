#############################################################
##
## This app file contains the variables of OPENSHIFT Installation
## on AWS
## 
## @year 2019
## @author Joe Gardiner <joe@grdnr.io>
##
#############################################################
### Region
variable "aws_region" {
  description = "The region to deploy the kubernetes clusters"
  default     = ""
}

variable "key_name" {
  description = "Key pair name to use for SSH"
  default     = ""
}

variable "private_key_path" {
  description = "Path to private SSH key"
  default     = ""
}

variable "app_sub_domain" {
  description = "Domain under which apps subdomain will be accessible"
  default     = ""
}
