output "id" {
  description = "The unique identifier (ID) of the policy"
  value       = try(aws_organizations_policy.main[0].id, "")
}

output "arn" {
  description = "Amazon Resource Name (ARN) of the policy"
  value       = try(aws_organizations_policy.main[0].arn, "")
}
