variable "account_id" {
  description = "AWS account ID used by the example."
  type        = string
}

variable "ami_owner_account_id" {
  description = "AWS account ID that owns the shared RHEL AMIs."
  type        = string
  default     = "<AMI_OWNER_ACCOUNT_ID>"
}

variable "web_az1_cidr" {
  description = "Placeholder CIDR for the web AZ1 subnet."
  type        = string
  default     = "<WEB_AZ1_CIDR>"
}

variable "web_az2_cidr" {
  description = "Placeholder CIDR for the web AZ2 subnet."
  type        = string
  default     = "<WEB_AZ2_CIDR>"
}

variable "web_az3_cidr" {
  description = "Placeholder CIDR for the web AZ3 subnet."
  type        = string
  default     = "<WEB_AZ3_CIDR>"
}

variable "tripwire_cidr" {
  description = "Placeholder CIDR for the Tripwire endpoint."
  type        = string
  default     = "<TRIPWIRE_CIDR>"
}
