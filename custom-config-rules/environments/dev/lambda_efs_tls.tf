############################################################
#    EFS TLS Enforcement Lambda Rule - Single Account     #
#                    (Dev Testing)                         #
############################################################

# Deploy Lambda function with account-level Config rule
# (NOT organization-wide for dev testing)

module "efs_tls_enforcement_dev" {
  source            = "../../modules/lambda_rule"
  organization_rule = false  # Single account only for testing
  create_config_rule = true
  config_rule_name  = "efs-tls-enforcement-dev"
  description       = "Custom Lambda rule to validate EFS file system policies enforce TLS (aws:SecureTransport) - DEV TESTING"
  lambda_script_dir = "../../scripts/efs-tls-enforcement"
  
  resource_types_scope = ["AWS::EFS::FileSystem"]
  trigger_types        = ["ConfigurationItemChangeNotification"]
  
  # Additional IAM policy for EFS permissions
  additional_policies = [
    file("../../iam/efs-tls-enforcement.json")
  ]
}
