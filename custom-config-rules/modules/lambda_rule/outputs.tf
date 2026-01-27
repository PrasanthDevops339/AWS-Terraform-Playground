output "lambda_arn" {
  description = "ARN of the Lambda function"
  value       = module.lambda.lambda_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.lambda.lambda_function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.lambda_role.iam_role_arn
}

output "config_rule_name" {
  description = "Name of the Config rule"
  value       = var.config_rule_name
}
