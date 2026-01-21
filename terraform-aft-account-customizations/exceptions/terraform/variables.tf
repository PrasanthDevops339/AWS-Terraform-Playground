
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "account_name" {
  type = string
}

variable "environment" {
  type    = string
  default = "prd"
}

variable "kms_key_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "config_resource_types" {
  type        = list(string)
  description = "Which resource types to evaluate for tag compliance."
  default = [
    "AWS::EC2::Instance",
    "AWS::EC2::Volume",
    "AWS::RDS::DBInstance"
  ]
}
