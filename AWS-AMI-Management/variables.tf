# ============================================================================
# INPUT VARIABLES
# ============================================================================
# Variables define the configurable inputs for this Terraform module
# Users customize these values via terraform.tfvars file

# AWS Region (optional, mainly for provider configuration)
variable "aws_region" {
  description = "AWS region"    # Human-readable description
  type        = string          # Data type validation
  default     = "us-east-1"     # Default value if not provided
}

# Organization Root ID (REQUIRED - no default)
variable "org_root_id" {
  description = "AWS Organization Root ID to attach policies to" # Must start with 'r-'
  type        = string                                            # String type
  # No default = required input
}

# Ops Golden AMI Publisher Account
variable "ops_publisher_account" {
  description = "Ops Golden AMI Publisher Account ID" # Central AMI pipeline account
  type        = string                                 # 12-digit AWS account ID
  default     = "123456738923"                         # Default ops account
}

# Approved Vendor AMI Publisher Accounts
variable "vendor_publisher_accounts" {
  description = "List of vendor AMI publisher account IDs" # Third-party approved vendors
  type        = list(string)                                # List of strings (account IDs)
  default = [
    "111122223333", # InfoBlox - DNS/DHCP appliances
    "444455556666"  # Terraform Enterprise - private TFE AMIs
  ]
}

# Temporary Exception Accounts (with expiry dates)
variable "exception_accounts" {
  description = "Map of exception account IDs to expiry dates (YYYY-MM-DD)" # Time-bound exceptions
  type        = map(string)                                                 # Map: account_id => expiry_date
  default = {
    "777788889999" = "2026-02-28" # Migration exception - expires end of Feb 2026
    "222233334444" = "2026-03-15" # ML POC exception - expires mid-March 2026
  }
}

# Enforcement Mode (audit vs. blocking)
variable "enforcement_mode" {
  description = "Declarative policy enforcement mode: audit_mode or enabled" # Controls blocking behavior
  type        = string                                                      # String value
  default     = "audit_mode"                                                # Start with audit (log only, no block)

  # Validation block ensures only valid values are accepted
  validation {
    condition     = contains(["audit_mode", "enabled"], var.enforcement_mode) # Check if value is in list
    error_message = "enforcement_mode must be either 'audit_mode' or 'enabled'" # Error shown if validation fails
  }
}

# Exception Request URL (shown in error messages)
variable "exception_request_url" {
  description = "URL for exception requests" # Where users submit exception requests
  type        = string                       # URL as string
  default     = "https://jira.company.com"   # Default ticketing system URL
}

# Resource Tags (applied to all policies)
variable "tags" {
  description = "Tags to apply to all resources" # Common tags for organization
  type        = map(string)                      # Key-value pairs
  default = {
    ManagedBy   = "Terraform"      # Indicates infrastructure is code-managed
    Feature     = "AMI-Governance" # Feature/capability grouping
    Environment = "production"     # Environment designation
  }
}
