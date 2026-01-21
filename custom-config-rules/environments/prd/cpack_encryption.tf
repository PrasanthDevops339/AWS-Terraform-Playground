############################################################
#                         USE2                             #
############################################################
module "cpack_encryption" {
  source            = "../../modules/conformance_pack"
  cpack_name        = "encryption-validation"
  organization_pack = true
  excluded_accounts = [
    "000000000000",
    "066777777777",
    "999999990618",
    "666666666739" # smrrnd-tst | config not config'd on account and SCP blocks it
  ]

  policy_rules_list = [
    {
      config_rule_name     = "ebs-is-encrypted"
      config_rule_version  = "2026-01-09"
      description          = "Config Rule for checking if an EBS Volume is encrypted"
      resource_types_scope = ["AWS::EC2::Volume", "AWS::EC2::Snapshot"]
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

############################################################
#                         USE1                             #
############################################################
module "cpack_encryption_use1" {
  source = "../../modules/conformance_pack"

  providers = {
    aws = aws.use1
  }

  cpack_name        = "encryption-validation"
  organization_pack = true
  excluded_accounts = [
    "000000000000",
    "066777777777",
    "999999990618",
    "666666666739"  # smrrnd-tst | config not config'd on account and SCP blocks it
  ]

  policy_rules_list = [
    {
      config_rule_name     = "ebs-is-encrypted"
      config_rule_version  = "2026-01-09"
      description          = "Config Rule for checking if an EBS Volume is encrypted"
      resource_types_scope = ["AWS::EC2::Volume", "AWS::EC2::Snapshot"]
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
