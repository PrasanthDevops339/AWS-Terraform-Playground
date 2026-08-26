output "aws_cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "ID of the user pool"
}

output "aws_cognito_user_pool_arn" {
  value       = aws_cognito_user_pool.main.arn
  description = "ARN of the user pool"
}

output "aws_cognito_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "domain of the user pool"
}

output "aws_cognito_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "client id of user pool"
}
