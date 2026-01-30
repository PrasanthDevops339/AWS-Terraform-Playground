variable "key_name" {
  description = "The name of the kms key"
  type        = string

  validation {
    condition     = length(var.key_name) >= 3
    error_message = "Must provide an alias and length must be at least 3 characters"
  }
}

variable "replica_key_name" {
  description = "The name of the replica kms key"
  type        = string
  default     = ""

  validation {
    condition = (
      (var.enable_region_argument == true && var.enable_replica == true && length(var.replica_key_name) >= 3) ||
      (var.enable_region_argument == true && var.enable_replica == true && length(var.replica_key_name) == 0 && length(var.key_name) >= 3) ||
      (var.enable_region_argument == true && var.enable_replica == false && length(var.replica_key_name) == 0) ||
      (var.enable_region_argument == false && length(var.replica_key_name) == 0)
    )
    error_message = "Must provide an alias and length must be at least 3 characters"
  }
}

variable "primary_key_arn" {
  description = "The primary key arn of a multi-region replica key"
  type        = string
  default     = null
}

variable "deletion_window_in_days" {
  description = "Duration in days after which the key is deleted after destruction of the resource, must be between 7 and 30 days"
  type        = number
  default     = 7
}

variable "description" {
  description = "The description of the key as viewed in AWS console"
  type        = string
  default     = "The Customer managed KMS key, created from the module"
}

variable "enable_creation" {
  description = "enable resource creation"
  type        = bool
  default     = true
}

variable "enable_key" {
  description = "Specifies whether the key is enabled"
  type        = bool
  default     = true
}

variable "enable_replica" {
  description = "Mark KMS key as a replica key"
  type        = bool
  default     = false
}

variable "enable_region_argument" {
  description = "Enable aws provider 6.X region configuration"
  type        = bool
  default     = false
}

variable "secondary_region" {
  description = "Secondary region of replica key"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.secondary_region == "us-east-1" || var.secondary_region == "us-east-2"
    error_message = "secondary_region can only be us-east-1 or us-east-2"
  }
}

variable "key_statements" {
  description = "A map of IAM policy statements for custom permission usage"
  type        = any
  default     = {}
}

variable "replica_key_statements" {
  description = "A map of IAM policy statements for custom permission usage for replica key"
  type        = any
  default     = {}
}

variable "policy_file" {
  description = "IAM policy file that will append IAM statements to key policy"
  type        = string
  default     = "{}"
}

variable "replica_policy_file" {
  description = "IAM policy file that will append IAM statements to replica key policy"
  type        = string
  default     = "{}"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
