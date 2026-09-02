# The user pool ARN carries its Region in the 4th field, so this is the
# cheapest proof that `region` actually moved the resources. After apply it
# must read us-east-1, not the us-east-2 the provider is configured for.
output "user_pool_arn" {
  description = "ARN of the user pool. Confirm the Region field reads us-east-1."
  value       = module.cognitotest.aws_cognito_user_pool_arn
}

output "user_pool_region" {
  description = "Region parsed out of the user pool ARN. Should equal us-east-1."
  value       = split(":", module.cognitotest.aws_cognito_user_pool_arn)[3]
}

output "web_acl_arn" {
  description = "ARN of the Web ACL the pool is associated with. Its Region must match user_pool_region."
  value       = module.waf.arn
}

output "provider_region" {
  description = "Region the default aws provider is configured for, for contrast with user_pool_region."
  value       = "us-east-2"
}
