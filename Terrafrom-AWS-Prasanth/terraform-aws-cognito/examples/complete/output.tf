# Mirrors ../complete-use1/output.tf, asserting the opposite: with no `region`
# set, the pool stays in the provider's Region.
output "user_pool_arn" {
  description = "ARN of the user pool. Confirm the Region field reads us-east-2."
  value       = module.cognitotest.aws_cognito_user_pool_arn
}

output "user_pool_region" {
  description = "Region parsed out of the user pool ARN. Should equal provider_region, since this example does not set the module's region input."
  value       = split(":", module.cognitotest.aws_cognito_user_pool_arn)[3]
}

output "web_acl_arn" {
  description = "ARN of the Web ACL the pool is associated with. Its Region must match user_pool_region."
  value       = module.waf.arn
}

output "provider_region" {
  description = "Region the aws provider is configured for. Equals user_pool_region in this example."
  value       = "us-east-2"
}
