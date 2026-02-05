###############################################################################
# module to create lambda functions that integrates with the Conformance pack #
###############################################################################

module "backup_tags_compliance" {
  source = "../../modules/lambda"
  lambda_name = "backup-tags"
  policy_document = templatefile("../../modules/policy-files/tags_compliance.json", {
    region     = data.aws_region.current.name,
    account_id = data.aws_caller_identity.current.account_id
  })
  lambda_script_dir = "../../modules/scripts/backup-tags/"
  lambda_handler    = "backup_tags.lambda_handler"
  runtime           = "python3.12"
  principal         = "config.amazonaws.com"
}

module "patching_tags_compliance" {
  source = "../../modules/lambda"
  lambda_name = "patching-tags"
  policy_document = templatefile("../../modules/policy-files/tags_compliance.json", {
    region     = data.aws_region.current.name,
    account_id = data.aws_caller_identity.current.account_id
  })
  lambda_script_dir = "../../modules/scripts/patching-tags/"
  lambda_handler    = "patching_tags.lambda_handler"
  runtime           = "python3.12"
  principal         = "config.amazonaws.com"
}

module "finops_tags_compliance" {
  source = "../../modules/lambda"
  lambda_name = "finops-tags"
  policy_document = templatefile("../../modules/policy-files/tags_compliance.json", {
    region     = data.aws_region.current.name,
    account_id = data.aws_caller_identity.current.account_id
  })
  lambda_script_dir = "../../modules/scripts/finops-tags/"
  lambda_handler    = "finops_tags.lambda_handler"
  runtime           = "python3.12"
  principal         = "config.amazonaws.com"
}

module "platform_tags_compliance" {
  source = "../../modules/lambda"
  lambda_name = "platform-tags"
  policy_document = templatefile("../../modules/policy-files/tags_compliance.json", {
    region     = data.aws_region.current.name,
    account_id = data.aws_caller_identity.current.account_id
  })
  lambda_script_dir = "../../modules/scripts/platform-tags/"
  lambda_handler    = "platform_tags.lambda_handler"
  runtime           = "python3.12"
  principal         = "config.amazonaws.com"
}

###############################################################################
# Conformance pack that deploye Config Rules for tag enforcement              #
###############################################################################

resource "aws_config_conformance_pack" "tagenforcement" {
  name = "Taggingconformancepack"

  template_body = <<EOT
Resources:
  backuptags:
    Properties:
      ConfigRuleName: backuptags_${data.aws_caller_identity.current.account_id}
      Scope:
        ComplianceResourceTypes:
          - "AWS::EC2::Instance"
          - "AWS::EC2::Volume"
          - "AWS::DynamoDB::Table"
          - "AWS::EFS::FileSystem"
          - "AWS::S3::Bucket"
          - "AWS::RDS::DBInstance"
      Source:
        Owner: CUSTOM_LAMBDA
        SourceIdentifier: "${module.backup_tags_compliance.lambda_arn}"
        SourceDetails:
          - EventSource: "aws.config"
            MessageType: "ConfigurationItemChangeNotification"
      Type: AWS::Config::ConfigRule

  patchingtags:
    Properties:
      ConfigRuleName: patchingtags_${data.aws_caller_identity.current.account_id}
      Scope:
        ComplianceResourceTypes:
          - "AWS::EC2::Instance"
          - "AWS::EC2::Volume"
      Source:
        Owner: CUSTOM_LAMBDA
        SourceIdentifier: "${module.patching_tags_compliance.lambda_arn}"
        SourceDetails:
          - EventSource: "aws.config"
            MessageType: "ConfigurationItemChangeNotification"
      Type: AWS::Config::ConfigRule

  finopstags:
    Properties:
      ConfigRuleName: finopstags_${data.aws_caller_identity.current.account_id}
      Source:
        Owner: CUSTOM_LAMBDA
        SourceIdentifier: "${module.finops_tags_compliance.lambda_arn}"
        SourceDetails:
          - EventSource: "aws.config"
            MessageType: "ConfigurationItemChangeNotification"
      Type: AWS::Config::ConfigRule

  platformtags:
    Properties:
      ConfigRuleName: platformtags_${data.aws_caller_identity.current.account_id}
      Source:
        Owner: CUSTOM_LAMBDA
        SourceIdentifier: "${module.platform_tags_compliance.lambda_arn}"
        SourceDetails:
          - EventSource: "aws.config"
            MessageType: "ConfigurationItemChangeNotification"
      Type: AWS::Config::ConfigRule
EOT

  depends_on = [module.backup_tags_compliance]
}

