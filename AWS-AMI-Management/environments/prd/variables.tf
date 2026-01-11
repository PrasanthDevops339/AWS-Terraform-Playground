# ============================================================================
# PRODUCTION ENVIRONMENT VARIABLES
# ============================================================================
# Variable definitions for production AMI governance deployment

# AWS Region
variable "aws_region" {
  description = "AWS region for provider configuration" # Default region
  type        = string                                  # String type
  default     = "us-east-1"                             # US East (N. Virginia)
}

# Environment Identifier
variable "environment" {
  description = "Environment which aligns to account 'dev', 'prd'" # Environment designation
  type        = string                                             # String type

  # Validation to ensure only valid environments
  validation {
    condition     = contains(["dev", "prd"], var.environment)
    error_message = "Valid values for environment are 'dev' or 'prd'"
  }
}

# Target IDs for Policy Attachment
variable "target_ids" {
  description = "List of target IDs (Root/OU/Account) to attach AMI governance policies to" # Where policies apply
  type        = list(string)                                                                # List of IDs
}

# Ops Golden AMI Publisher Account
variable "ops_publisher_account" {
  description = "Ops Golden AMI Publisher Account ID" # Central AMI pipeline account
  type        = string                                 # 12-digit AWS account ID
}

# Vendor Publisher Accounts
variable "vendor_publisher_accounts" {
  description = "List of approved vendor AMI publisher account IDs" # Third-party vendors
  type        = list(string)                                        # List of account IDs
  default     = []                                                  # Empty by default
}

# Exception Accounts with Expiry Dates
variable "exception_accounts" {
  description = "Map of exception account IDs to expiry dates (YYYY-MM-DD format)" # Time-bound exceptions
  type        = map(string)                                                         # Map: account => date
  default     = {}                                                                  # Empty by default
}

# Enforcement Mode
variable "enforcement_mode" {
  description = "Declarative policy enforcement mode: audit_mode (log only) or enabled (block)" # Controls blocking
  type        = string                                                                           # String value
  default     = "audit_mode"                                                                     # Safe default

  # Validation block
  validation {
    condition     = contains(["audit_mode", "enabled"], var.enforcement_mode)
    error_message = "enforcement_mode must be either 'audit_mode' or 'enabled'"
  }
}

# Exception Request URL
variable "exception_request_url" {
  description = "URL for users to request AMI governance exceptions" # Ticketing system URL
  type        = string                                                # String type
  default     = "https://jira.company.com/browse/CLOUD"               # Default Jira project
}

# Resource Tags
variable "tags" {
  description = "Common tags to apply to all AMI governance resources" # Organization tags
  type        = map(string)                                            # Key-value pairs
  default = {
    ManagedBy   = "Terraform"      # Infrastructure as Code indicator
    Feature     = "AMI-Governance" # Feature grouping
    Environment = "production"     # Environment designation
    CostCenter  = "CloudSec"       # Cost allocation
  }
}
