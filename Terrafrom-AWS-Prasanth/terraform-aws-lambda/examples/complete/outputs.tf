# lambda outputs

output "lambda_arn" {
  description = "The ARN(Amazon Resource Name) of the lambda function"
  value       = module.lambda-complete.lambda_arn
}

output "lambda_function_name" {
  description = "The name of the lambda function"
  value       = module.lambda-complete.lambda_function_name
}
