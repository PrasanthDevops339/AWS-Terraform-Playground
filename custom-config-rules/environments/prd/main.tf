module "port_443_is_open" {
  source             = "../../modules/policy_rule"
  organization_rule  = true
  config_rule_name   = "port-443-is-open"
  config_rule_version = "2025-06-27"
  description        = "Rule for detecting instances that don't have 443 open"
  resource_types_scope = ["AWS::EC2::SecurityGroup"]
  excluded_accounts = [
    "667863416739" # smrrnd-tst | config not config'd on account and SCP blocks it
  ]
}

# module "check_for_ssm_permissions" {
#   source             = "../../modules/lambda_rule"
#   organization_rule  = true
#   config_rule_name   = "check-for-ssm-permissions"
#   description        = "Rule for check an instance's profile so that it does not have certain permissions"
#   lambda_script_dir  = "../../scripts/check-for-ssm-permissions"
#   resource_types_scope = ["AWS::IAM::Role", "AWS::IAM::Policy"]
#   additional_policies = [
#     file("../../iam/check-for-ssm-permissions.json")
#   ]
#   excluded_accounts = [
#     "667863416739" # smrrnd-tst | config not config'd on account and SCP blocks it
#   ]
# }
