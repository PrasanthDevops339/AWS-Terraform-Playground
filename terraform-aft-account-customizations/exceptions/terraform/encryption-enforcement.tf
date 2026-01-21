
#############################################
# Guard Policy Rules - Encryption & Config Validation
# Conformance Pack for EBS, SQS, and EFS
#############################################
#
# Purpose:
#   Deploys AWS Config conformance pack with Guard policy rules
#   to validate encryption and basic configuration compliance.
#
# What it does:
#   - Creates account-level conformance pack (AFT runs per-account)
#   - Validates encryption is enabled on EBS, SQS, EFS
#   - Checks for required tag presence
#   - Validates Environment tag values
#   - Checks EFS performance mode settings
#
# Deployment:
#   AFT automatically deploys this to each account during customization phase
#   Uses existing AWS Config recorder (managed by Control Tower)
#
# Resources Created:
#   - 1 Conformance pack containing 3 Guard policy rules
#   - Config rules triggered on resource configuration changes
#
# Guard Rules Included:
#   1. ebs-validation  - EBS volumes/snapshots encryption + tags
#   2. sqs-validation  - SQS queue encryption + Environment values
#   3. efs-validation  - EFS encryption + PerformanceMode + tags
#
#############################################

module "encryption_validation_conformance_pack" {
  source = "../../modules/conformance_pack"

  # Conformance pack name (will be prefixed with account alias)
  cpack_name = "encryption-validation"
  
  # Random ID suffix (null = no suffix)
  random_id  = null

  # List of Guard policy rules to include in the pack
  # Each rule references a .guard file in policies/ directory
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

