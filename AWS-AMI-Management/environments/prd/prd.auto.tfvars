# ============================================================================
# PRODUCTION ENVIRONMENT CONFIGURATION
# ============================================================================
# Auto-loaded configuration for production AMI governance deployment
# This file is automatically loaded by Terraform (*.auto.tfvars pattern)

# Environment designation
environment = "prd"

# Target IDs - Organizations Root/OUs/Accounts to attach policies to
# IMPORTANT: Update these with your actual Organization Root/OU IDs
target_ids = [
  "r-xxxx"  # Organization Root ID - apply to entire organization
  # "ou-xxxx-yyyyyyyy"  # Or specific OU IDs for targeted enforcement
]

# Ops Golden AMI Publisher Account
# This is the central AMI pipeline account that publishes approved golden AMIs
ops_publisher_account = "123456738923"

# Approved Vendor AMI Publisher Accounts
# Third-party vendors whose AMIs are pre-approved for use
vendor_publisher_accounts = [
  "111122223333",  # InfoBlox - DNS/DHCP appliances
  "444455556666",  # Terraform Enterprise - TFE AMIs
  # Add more vendor accounts as needed
]

# Exception Accounts with Expiry Dates
# Temporary exceptions for accounts that need to use non-standard AMIs
# Format: "account_id" = "YYYY-MM-DD" (expiry date)
exception_accounts = {
  # Example exceptions (update with actual accounts and dates):
  # "777788889999" = "2026-02-28"  # Migration project exception
  # "222233334444" = "2026-03-15"  # ML POC exception
  # "555566667777" = "2026-04-30"  # Special workload exception
}

# Enforcement Mode
# - "audit_mode": Log violations but don't block (recommended for initial deployment)
# - "enabled": Actively block non-compliant AMI launches (production enforcement)
enforcement_mode = "audit_mode"  # Start with audit mode, switch to "enabled" after validation

# Exception Request URL
# Users see this URL in error messages when blocked
exception_request_url = "https://jira.company.com/browse/CLOUD"

# Resource Tags
# Applied to all AMI governance policies
tags = {
  ManagedBy   = "Terraform"
  Feature     = "AMI-Governance"
  Environment = "production"
  CostCenter  = "CloudSec"
  Owner       = "cloud-platform-team@company.com"
}
