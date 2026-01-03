##################################################
# Outputs
##################################################

output "declarative_policy_id" {
  description = "ID of the EC2 declarative policy"
  value       = var.enable_declarative_policy ? aws_organizations_policy.ami_declarative_policy[0].id : null
}

output "declarative_policy_arn" {
  description = "ARN of the EC2 declarative policy"
  value       = var.enable_declarative_policy ? aws_organizations_policy.ami_declarative_policy[0].arn : null
}

output "scp_policy_id" {
  description = "ID of the SCP policy"
  value       = var.enable_scp_policy ? aws_organizations_policy.ami_scp_policy[0].id : null
}

output "scp_policy_arn" {
  description = "ARN of the SCP policy"
  value       = var.enable_scp_policy ? aws_organizations_policy.ami_scp_policy[0].arn : null
}

output "attached_ou_ids" {
  description = "List of OU IDs where policies are attached"
  value       = var.org_root_or_ou_ids
}

output "approved_ami_owners" {
  description = "List of all approved AMI owner account IDs (including active exceptions)"
  value       = local.all_allowed_ami_owners
}

output "active_exceptions" {
  description = "Map of active exception accounts and their expiry dates"
  value       = local.active_exceptions
}

output "expired_exceptions" {
  description = "Map of expired exception accounts"
  value = {
    for account, expiry in var.exception_accounts :
    account => expiry
    if timecmp(expiry, local.current_date_str) < 0
  }
}

output "exception_expiry_sns_topic_arn" {
  description = "ARN of SNS topic for exception expiry notifications"
  value       = aws_sns_topic.ami_exception_expiry.arn
}

output "exception_tracking_parameter" {
  description = "SSM Parameter name storing exception tracking data"
  value       = aws_ssm_parameter.ami_exceptions.name
}

output "policy_mode" {
  description = "Current policy enforcement mode"
  value       = var.policy_mode
}

output "policy_summary" {
  description = "Summary of the AMI governance policy configuration"
  value = {
    declarative_policy_enabled = var.enable_declarative_policy
    scp_policy_enabled        = var.enable_scp_policy
    policy_mode               = var.policy_mode
    total_approved_owners     = length(local.all_allowed_ami_owners)
    permanent_approved_owners = length(var.approved_ami_owner_accounts)
    active_exceptions_count   = length(local.active_exceptions)
    target_ou_count          = length(var.org_root_or_ou_ids)
    workload_ou_count        = length(local.scp_target_ou_ids)
  }
}
