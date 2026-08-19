output "detect_document_name" {
  description = "Command document run on the instance."
  value       = aws_ssm_document.detect.name
}

output "trigger_document_name" {
  description = "Automation runbook targeted by EventBridge."
  value       = aws_ssm_document.trigger.name
}

output "automation_role_arn" {
  description = "Automation execution role ARN passed in the event input template."
  value       = aws_iam_role.automation.arn
}

output "events_role_arn" {
  description = "Role EventBridge assumes to start the Automation."
  value       = aws_iam_role.events.arn
}

output "event_rule_arn" {
  description = "EventBridge rule reacting to patch command completion."
  value       = aws_cloudwatch_event_rule.patch_command_complete.arn
}

output "metric_namespace" {
  description = "Namespace to point Splunk Observability detectors at."
  value       = var.metric_namespace
}

output "instance_metric_policy_arn" {
  description = "Policy granting instances scoped PutMetricData, if created."
  value       = try(aws_iam_policy.instance_metrics[0].arn, null)
}
