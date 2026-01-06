variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "org_root_id" {
  description = "AWS Organization Root ID to attach policies to"
  type        = string
}

variable "ops_publisher_account" {
  description = "Ops Golden AMI Publisher Account ID"
  type        = string
  default     = "123456738923"
}

variable "vendor_publisher_accounts" {
  description = "List of vendor AMI publisher account IDs"
  type        = list(string)
  default = [
    "111122223333", # InfoBlox
    "444455556666"  # Terraform Enterprise
  ]
}

variable "exception_accounts" {
  description = "Map of exception account IDs to expiry dates (YYYY-MM-DD)"
  type        = map(string)
  default = {
    "777788889999" = "2026-02-28" # Migration exception
    "222233334444" = "2026-03-15" # ML POC exception
  }
}

variable "enforcement_mode" {
  description = "Declarative policy enforcement mode: audit_mode or enabled"
  type        = string
  default     = "audit_mode"

  validation {
    condition     = contains(["audit_mode", "enabled"], var.enforcement_mode)
    error_message = "enforcement_mode must be either 'audit_mode' or 'enabled'"
  }
}

variable "exception_request_url" {
  description = "URL for exception requests"
  type        = string
  default     = "https://jira.company.com"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Feature     = "AMI-Governance"
    Environment = "production"
  }
}
