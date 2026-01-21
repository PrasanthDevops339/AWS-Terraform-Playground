
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

#############################################
# Service Control Policy Variables
#############################################

variable "enable_ebs_scp" {
  type        = bool
  description = "Enable EBS governance SCP"
  default     = true
}

variable "enable_sqs_scp" {
  type        = bool
  description = "Enable SQS governance SCP"
  default     = true
}

variable "enable_efs_scp" {
  type        = bool
  description = "Enable EFS governance SCP"
  default     = true
}

variable "scp_attach_to_target" {
  type        = bool
  description = "Whether to attach SCPs to organizational unit or account"
  default     = false
}

variable "scp_target_id" {
  type        = string
  description = "The organizational unit ID or account ID to attach SCPs to"
  default     = null
}
