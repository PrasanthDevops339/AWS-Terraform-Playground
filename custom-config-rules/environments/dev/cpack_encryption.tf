module "cpack_encryption" {
  source     = "../../modules/conformance_pack"
  cpack_name = "encryption-validation"
  random_id  = local.random_id

  policy_rules_list = [
    {
      config_rule_name     = "ebs-is-encrypted"
      config_rule_version  = "2025-10-30"
      description          = "Config Rule for checking if an EBS Volume is encrypted"
      resource_types_scope = ["AWS::EC2::Volume"]
    },
    {
      config_rule_name     = "sqs-is-encrypted"
      config_rule_version  = "2025-10-30"
      description          = "Config Rule for checking if an SQS Queue is encrypted"
      resource_types_scope = ["AWS::SQS::Queue"]
    },
    {
      config_rule_name     = "efs-is-encrypted"
      config_rule_version  = "2025-10-30"
      description          = "Config Rule for checking if an EFS is encrypted"
      resource_types_scope = ["AWS::EFS::FileSystem"]
    }
  ]
}

# For Pre-Dev debugging
# output "template_yml" {
#   value = var.is_pre_dev ? module.cpack_encryption[0].template_yml : ""
# }
