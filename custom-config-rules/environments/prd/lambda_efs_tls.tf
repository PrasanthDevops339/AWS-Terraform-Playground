############################################################
#       EFS TLS Enforcement Lambda Rule - USE2             #
############################################################
# WHY THIS LAMBDA RULE EXISTS:
# EFS resource policies are NOT included in AWS Config configuration items.
# To validate TLS enforcement (aws:SecureTransport condition in resource policy):
# - Lambda must call elasticfilesystem:DescribeFileSystemPolicy API
# - Parse the JSON policy document
# - Check for Deny statement with "aws:SecureTransport": "false" condition
# - This cannot be done with Guard policy rules (no API calls, no access to policies)
#
# WHAT IT VALIDATES:
# - EFS file system has a resource policy attached
# - Policy contains Deny effect when SecureTransport is false
# - Ensures all connections to EFS must use TLS/encryption in transit
#
# COMPLEMENTS:
# - Guard policy (efs-is-encrypted) validates encryption-at-rest
# - This Lambda rule validates encryption-in-transit
module "efs_tls_enforcement" {
  source            = "../../modules/lambda_rule"
  organization_rule = true
  config_rule_name  = "efs-tls-enforcement"
  description       = "Custom Lambda rule to validate EFS file system policies enforce TLS (aws:SecureTransport)"
  lambda_script_dir = "../../scripts/efs-tls-enforcement"
  
  resource_types_scope = ["AWS::EFS::FileSystem"]
  trigger_types        = ["ConfigurationItemChangeNotification"]
  
  # Additional IAM policy for EFS permissions
  additional_policies = [
    file("../../iam/efs-tls-enforcement.json")
  ]
  
  excluded_accounts = [
    "667863416739" # smrrnd-tst | config not config'd on account and SCP blocks it
  ]
}

############################################################
#       EFS TLS Enforcement Lambda Rule - USE1             #
############################################################
# Same Lambda rule deployed to us-east-1 for multi-region coverage
# See USE2 section above for detailed explanation of why Lambda is needed
module "efs_tls_enforcement_use1" {
  source = "../../modules/lambda_rule"
  
  providers = {
    aws = aws.use1
  }
  
  organization_rule = true
  config_rule_name  = "efs-tls-enforcement"
  description       = "Custom Lambda rule to validate EFS file system policies enforce TLS (aws:SecureTransport)"
  lambda_script_dir = "../../scripts/efs-tls-enforcement"
  
  resource_types_scope = ["AWS::EFS::FileSystem"]
  trigger_types        = ["ConfigurationItemChangeNotification"]
  
  # Additional IAM policy for EFS permissions
  additional_policies = [
    file("../../iam/efs-tls-enforcement.json")
  ]
  
  excluded_accounts = [
    "667863416739" # smrrnd-tst | config not config'd on account and SCP blocks it
  ]
}
