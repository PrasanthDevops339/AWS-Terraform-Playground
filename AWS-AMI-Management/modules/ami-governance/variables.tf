# ============================================================================
# MODULE INPUT VARIABLES
# ============================================================================
# Variables for the AMI governance module
# These are passed from the environment-specific configurations

# Environment identifier (dev/prd)
variable "environment" {
  description = "Environment name (dev, prd)" # Environment designation
  type        = string                        # String type

  # Validation to ensure only valid environments
  validation {
    condition     = contains(["dev", "prd"], var.environment)
    error_message = "Valid values for environment are 'dev' or 'prd'"
  }
}

# Policy Names
variable "declarative_policy_name" {
  description = "Name for the declarative EC2 policy" # Human-readable policy name
  type        = string                                # String type
  default     = "ami-governance-declarative-policy"   # Default name
}

variable "scp_policy_name" {
  description = "Name for the SCP policy"      # Human-readable SCP name
  type        = string                         # String type
  default     = "scp-ami-guardrail"            # Default name
}

# Target IDs for policy attachments
variable "target_ids" {
  description = "List of target IDs (Root/OU/Account) to attach policies to" # Where policies apply
  type        = list(string)                                                 # List of IDs
}

# Ops Golden AMI Publisher Account
variable "ops_publisher_account" {
  description = "Ops Golden AMI Publisher Account ID" # Central AMI pipeline account
  type        = string                                 # 12-digit AWS account ID
}

# Approved Vendor AMI Publisher Accounts
variable "vendor_publisher_accounts" {
  description = "List of vendor AMI publisher account IDs" # Third-party approved vendors
  type        = list(string)                                # List of strings (account IDs)
  default     = []                                          # Empty list by default
}

# Temporary Exception Accounts (with expiry dates)
variable "exception_accounts" {
  description = "Map of exception account IDs to expiry dates (YYYY-MM-DD)" # Time-bound exceptions
  type        = map(string)                                                 # Map: account_id => expiry_date
  default     = {}                                                          # Empty map by default
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
  default     = {}                               # Empty map by default - environment provides tags
}
