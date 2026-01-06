output "declarative_policy_id" {
  description = "ID of the Declarative Policy for EC2"
  value       = aws_organizations_policy.declarative_ec2.id
}

output "declarative_policy_arn" {
  description = "ARN of the Declarative Policy for EC2"
  value       = aws_organizations_policy.declarative_ec2.arn
}

output "scp_policy_id" {
  description = "ID of the Service Control Policy"
  value       = aws_organizations_policy.scp.id
}

output "scp_policy_arn" {
  description = "ARN of the Service Control Policy"
  value       = aws_organizations_policy.scp.arn
}

output "approved_ami_owners" {
  description = "Complete list of approved AMI owner accounts"
  value       = local.sorted_allowlist
}

output "active_exceptions" {
  description = "Currently active exception accounts with expiry dates"
  value       = local.active_exceptions
}

output "expired_exceptions" {
  description = "Expired exception accounts that should be removed"
  value       = local.expired_exceptions
}

output "enforcement_mode" {
  description = "Current enforcement mode"
  value       = var.enforcement_mode
}

output "policy_summary" {
  description = "Summary of AMI governance policy configuration"
  value = {
    total_approved_accounts = length(local.sorted_allowlist)
    ops_publisher           = var.ops_publisher_account
    vendor_publishers       = var.vendor_publisher_accounts
    active_exceptions       = length(local.active_exceptions)
    expired_exceptions      = length(local.expired_exceptions)
    enforcement_mode        = var.enforcement_mode
  }
}
