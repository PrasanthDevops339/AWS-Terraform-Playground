############################################################
#       EFS TLS Enforcement Lambda Rule - USE2             #
############################################################
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
