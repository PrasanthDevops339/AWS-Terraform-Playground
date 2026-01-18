module "port_443_is_open" {
  source               = "../../modules/policy_rule"
  count                = var.is_pre_dev ? 0 : 1 # Dont need in pre-dev
  config_rule_name     = "port-443-is-open"
  config_rule_version  = "2025-06-27"
  description          = "Rule for detecting instances that don't have 443 open"
  resource_types_scope = ["AWS::EC2::SecurityGroup"]
  random_id            = local.random_id
}

module "ebs_rules_test_use2" {
  source               = "../../modules/policy_rule"
  count                = var.is_pre_dev ? 0 : 1 # Dont need in pre-dev
  config_rule_name     = "ebs-is-encrypted"
  config_rule_version  = "2026-01-09"
  description          = "Rules for the EBS encryption for volumes and snapshots"
  resource_types_scope = ["AWS::EC2::Volume", "AWS::EC2::Snapshot"]
  random_id            = local.random_id
}

############################################
#########         USE1         #############
############################################

module "ebs_rules_test_use1" {
  source = "../../modules/policy_rule"

  providers = {
    aws = aws.use1
  }

  count                = var.is_pre_dev ? 0 : 1 # Dont need in pre-dev
  config_rule_name     = "ebs-is-encrypted"
  config_rule_version  = "2026-01-09"
  description          = "Rules for the EBS encryption for volumes and snapshots"
  resource_types_scope = ["AWS::EC2::Volume", "AWS::EC2::Snapshot"]
  random_id            = local.random_id
}
