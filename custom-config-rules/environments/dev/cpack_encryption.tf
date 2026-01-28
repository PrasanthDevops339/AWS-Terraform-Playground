module "cpack_encryption" {
  source     = "../../modules/conformance_pack"
  cpack_name = "encryption-validation"
  random_id  = local.random_id

  policy_rules_list = [
    {
      config_rule_name     = "ebs-is-encrypted"
      config_rule_version  = "2026-01-09"
      description          = "Config Rule for checking if an EBS Volume is encrypted"
      resource_types_scope = ["AWS::EC2::Volume"]
    },
    {
      config_rule_name     = "sqs-is-encrypted"
      config_rule_version  = "2026-01-27"
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
  
  # Lambda Custom Rules (for dev testing)
  lambda_rules_list = [
    {
      config_rule_name     = "efs-tls-enforcement"
      description          = "Custom Lambda rule to validate EFS file system policies enforce TLS (aws:SecureTransport)"
      lambda_function_arn  = module.efs_tls_enforcement_dev.lambda_arn
      resource_types_scope = ["AWS::EFS::FileSystem"]
      message_type         = "ConfigurationItemChangeNotification"
    }
  ]
  
  # AWS Managed Rules (for testing managed rule support)
  managed_rules_list = [
    {
      config_rule_name     = "s3-bucket-versioning-enabled"
      description          = "Checks whether versioning is enabled for S3 buckets"
      source_identifier    = "S3_BUCKET_VERSIONING_ENABLED"
      resource_types_scope = ["AWS::S3::Bucket"]
      input_parameters     = {}
    },
    {
      config_rule_name     = "rds-storage-encrypted"
      description          = "Checks whether storage encryption is enabled for RDS DB instances"
      source_identifier    = "RDS_STORAGE_ENCRYPTED"
      resource_types_scope = ["AWS::RDS::DBInstance"]
      input_parameters     = {}
    }
  ]
  
  depends_on = [
    module.efs_tls_enforcement_dev
  ]
}

# For Pre-Dev debugging
# output "template_yml" {
#   value = var.is_pre_dev ? module.cpack_encryption[0].template_yml : ""
# }
