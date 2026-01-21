
output "lambda_arn" {
  value       = local.lambda_arn
  description = "Lambda ARN (created or placeholder if not created)."
}

output "lambda_function_name" {
  value       = var.create_lambda_function ? aws_lambda_function.lambda_function[0].function_name : null
  description = "Lambda function name."
}

output "lambda_role_arn" {
  value       = var.lambda_role_arn != null ? var.lambda_role_arn : (length(aws_iam_role.lambda) > 0 ? aws_iam_role.lambda[0].arn : null)
  description = "Lambda role ARN (created or passed in)."
}

output "sns_topic_arn" {
  value       = local.sns_topic_arn
  description = "SNS topic ARN used for trigger (created or passed in)."
}

output "log_group_name" {
  value = var.use_custom_log_group ? var.log_group_name : (
    length(aws_cloudwatch_log_group.lambda_cloudwatch_log_group) > 0 ? aws_cloudwatch_log_group.lambda_cloudwatch_log_group[0].name : null
  )
  description = "CloudWatch log group name (created or custom)."
}
