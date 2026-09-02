# user_pool_region vs provider_region is the proof that `region` took effect.
output "user_pool_arn" {
  description = "ARN of the user pool. Confirm the Region field reads us-east-1."
  value       = module.cognitotest.aws_cognito_user_pool_arn
}

output "user_pool_region" {
  description = "Region parsed out of the user pool ARN. Should equal us-east-1."
  value       = provider::aws::arn_parse(module.cognitotest.aws_cognito_user_pool_arn).region
}

output "web_acl_arn" {
  description = "ARN of the Web ACL the pool is associated with. Its Region must match user_pool_region."
  value       = module.waf.arn
}

output "provider_region" {
  description = "Region the default aws provider is configured for, for contrast with user_pool_region."
  value       = "us-east-2"
}
