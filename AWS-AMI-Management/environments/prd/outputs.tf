# ============================================================================
# PRODUCTION ENVIRONMENT OUTPUTS
# ============================================================================
# Outputs from the production AMI governance deployment
# These expose the module outputs for reference and automation

# Declarative Policy Information
output "declarative_policy_id" {
  description = "ID of the deployed Declarative Policy for EC2"
  value       = module.ami_governance.declarative_policy_id
}

output "declarative_policy_arn" {
  description = "ARN of the deployed Declarative Policy for EC2"
  value       = module.ami_governance.declarative_policy_arn
}

# Service Control Policy Information
output "scp_policy_id" {
  description = "ID of the deployed Service Control Policy"
  value       = module.ami_governance.scp_policy_id
}

output "scp_policy_arn" {
  description = "ARN of the deployed Service Control Policy"
  value       = module.ami_governance.scp_policy_arn
}

# AMI Allowlist
output "approved_ami_owners" {
  description = "Complete list of approved AMI owner account IDs"
  value       = module.ami_governance.approved_ami_owners
}

# Exception Management
output "active_exceptions" {
  description = "Currently active exception accounts with expiry dates"
  value       = module.ami_governance.active_exceptions
}

output "expired_exceptions" {
  description = "EXPIRED exception accounts that need to be removed"
  value       = module.ami_governance.expired_exceptions
}

# Policy Configuration Summary
output "enforcement_mode" {
  description = "Current enforcement mode (audit_mode or enabled)"
  value       = module.ami_governance.enforcement_mode
}

output "policy_summary" {
  description = "Comprehensive summary of AMI governance configuration"
  value       = module.ami_governance.policy_summary
}
