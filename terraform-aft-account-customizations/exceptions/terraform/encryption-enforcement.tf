
#############################################
# Guard Policy Rules - Encryption & Config Validation
# Conformance Pack for EBS, SQS, and EFS
#############################################

module "encryption_validation_conformance_pack" {
  source = "../../modules/conformance_pack"

  cpack_name = "encryption-validation"
  random_id  = null

  policy_rules_list = [
    {
      config_rule_name     = "ebs-validation"
      config_rule_version  = "2026-01-21"
      description          = "Validates EBS volumes and snapshots are encrypted and have required tags"
      resource_types_scope = ["AWS::EC2::Volume", "AWS::EC2::Snapshot"]
    },
    {
      config_rule_name     = "sqs-validation"
      config_rule_version  = "2026-01-21"
      description          = "Validates SQS queues are encrypted and have required tags with valid values"
      resource_types_scope = ["AWS::SQS::Queue"]
    },
    {
      config_rule_name     = "efs-validation"
      config_rule_version  = "2026-01-21"
      description          = "Validates EFS file systems are encrypted with valid performance mode and required tags"
      resource_types_scope = ["AWS::EFS::FileSystem"]
    }
  ]
}
