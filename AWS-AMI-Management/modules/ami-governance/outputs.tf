# ============================================================================
# MODULE OUTPUTS
# ============================================================================
# Outputs expose important information after Terraform apply
# Use these values for documentation, automation, or references in other modules

# Declarative Policy Identifiers
output "declarative_policy_id" {
  description = "ID of the Declarative Policy for EC2"          # Policy ID (p-xxxxxxxx)
  value       = aws_organizations_policy.declarative_ec2.id     # Reference to policy resource
}

output "declarative_policy_arn" {
  description = "ARN of the Declarative Policy for EC2"         # Full ARN for API calls
  value       = aws_organizations_policy.declarative_ec2.arn    # Amazon Resource Name
}

# Service Control Policy Identifiers
output "scp_policy_id" {
  description = "ID of the Service Control Policy"              # SCP ID (p-xxxxxxxx)
  value       = aws_organizations_policy.scp.id                 # Reference to SCP resource
}

output "scp_policy_arn" {
  description = "ARN of the Service Control Policy"             # Full ARN for API calls
  value       = aws_organizations_policy.scp.arn                # Amazon Resource Name
}

# Allowlist Information
output "approved_ami_owners" {
  description = "Complete list of approved AMI owner accounts"   # Full allowlist used in policies
  value       = local.sorted_allowlist                          # Sorted list of account IDs
}

# Exception Tracking
output "active_exceptions" {
  description = "Currently active exception accounts with expiry dates" # Exceptions not yet expired
  value       = local.active_exceptions                                 # Map of account => expiry_date
}

output "expired_exceptions" {
  description = "Expired exception accounts that should be removed" # Exceptions past their expiry date
  value       = local.expired_exceptions                            # Map of account => expiry_date (EXPIRED)
}

# Policy Configuration
output "enforcement_mode" {
  description = "Current enforcement mode"    # Shows if policy is in audit or enforcement mode
  value       = var.enforcement_mode          # audit_mode or enabled
}

# Comprehensive Summary Output
output "policy_summary" {
  description = "Summary of AMI governance policy configuration" # High-level statistics
  value = {
    total_approved_accounts = length(local.sorted_allowlist)    # Total count of approved accounts
    ops_publisher           = var.ops_publisher_account         # Ops golden AMI account
    vendor_publishers       = var.vendor_publisher_accounts     # List of vendor accounts
    active_exceptions       = length(local.active_exceptions)   # Count of active exceptions
    expired_exceptions      = length(local.expired_exceptions)  # Count of expired exceptions (should be 0)
    enforcement_mode        = var.enforcement_mode              # Current mode (audit or enabled)
    target_ids              = var.target_ids                    # Where policies are attached
  }
}
