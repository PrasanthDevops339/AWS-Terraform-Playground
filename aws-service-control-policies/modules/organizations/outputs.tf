output "id" {
  description = "The unique identifier (ID) of the policy"
  value       = try(aws_organizations_policy.main[0].id, "")
}

output "arn" {
  description = "Amazon Resource Name (ARN) of the policy"
  value       = try(aws_organizations_policy.main[0].arn, "")
}

# Exception expiry outputs (visible only when enable_exception_expiry = true)
output "active_exception_accounts" {
  description = "Currently active (non-expired) exception accounts"
  value       = var.enable_exception_expiry ? local.active_exceptions : {}
}

output "expired_exception_accounts" {
  description = "Expired exception accounts (no longer applied)"
  value       = var.enable_exception_expiry ? local.expired_exceptions : {}
}
