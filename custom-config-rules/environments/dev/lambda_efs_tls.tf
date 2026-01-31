############################################################
#    EFS TLS Enforcement Lambda Rule - Single Account     #
#                    (Dev Testing)                         #
############################################################
# WHY THIS DEV DEPLOYMENT EXISTS:
# Tests Lambda rule in isolated account before org-wide rollout
# - organization_rule = false (single account only)
# - Separate config rule name (efs-tls-enforcement-dev)
# - Allows validation of Lambda logic without affecting production
# - Used to test: API calls, policy parsing, compliance evaluation
#
# WHY LAMBDA INSTEAD OF GUARD:
# EFS resource policies require elasticfilesystem:DescribeFileSystemPolicy API call
# Guard policy rules cannot make API calls - only evaluate Config item data
# Resource policies are NOT in Config items, so Lambda is required

# Deploy Lambda function with account-level Config rule
# (NOT organization-wide for dev testing)
# Only create in pre-dev environment (is_pre_dev = true)

module "efs_tls_enforcement_dev" {
  count             = var.is_pre_dev ? 1 : 0
  source            = "../../modules/lambda_rule"
  organization_rule = false  # Single account only for testing
  create_config_rule = true
  config_rule_name  = "efs-tls-enforcement-dev-${local.random_id}"
  description       = "Custom Lambda rule to validate EFS file system policies enforce TLS (aws:SecureTransport) - DEV TESTING"
  lambda_script_dir = "../../scripts/efs-tls-enforcement"
  random_id         = local.random_id
  
  resource_types_scope = ["AWS::EFS::FileSystem"]
  trigger_types        = ["ConfigurationItemChangeNotification"]
  
  # Additional IAM policy for EFS permissions
  additional_policies = [
    file("../../iam/efs-tls-enforcement.json")
  ]
}
