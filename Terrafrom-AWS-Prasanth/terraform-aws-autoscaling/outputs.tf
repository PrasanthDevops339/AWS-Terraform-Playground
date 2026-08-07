output "launch_template_id" {
  description = "Auto Scaling Group arn"
  value       = try(aws_launch_template.main[0].id, null)
}

output "launch_template_arn" {
  description = "Auto Scaling Group arn"
  value       = try(aws_launch_template.main[0].arn, null)
}

output "launch_template_latest_version" {
  description = "Auto Scaling Group arn"
  value       = try(aws_launch_template.main[0].latest_version, null)
}

output "autoscaling_group_id" {
  description = "Auto Scaling Group id"
  value       = try(aws_autoscaling_group.main[0].id, null)
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group id"
  value       = try(aws_autoscaling_group.main[0].name, null)
}

output "autoscaling_group_arn" {
  description = "Auto Scaling Group arn"
  value       = try(aws_autoscaling_group.main[0].arn, null)
}

output "autoscaling_policy_arns" {
  description = "ARNs of autoscaling policies"
  value       = { for k, v in aws_autoscaling_policy.main : k => v.arn }
}
