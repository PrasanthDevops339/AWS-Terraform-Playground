###############################################################################
# Lambda-Based Custom Config Rules - API Validation                           #
# Conformance Pack for EFS TLS Enforcement                                    #
###############################################################################
#
# Purpose:
#   Deploys Lambda-based AWS Config custom rules that require
#   AWS API calls to retrieve data not in Config items
#
# Why Lambda over Guard:
#   - EFS resource policies are NOT in Config items
#   - Requires elasticfilesystem:DescribeFileSystemPolicy API call
#   - Complex JSON policy parsing and validation
#   - Conditional evaluation of Deny statements
#
# Deployment:
#   AFT deploys these to each account during customization phase
#   Lambda functions packaged from modules/scripts/
#
# Rules Deployed:
#   1. efs-tls-enforcement - EFS TLS policy validation
#
###############################################################################

###############################################################################
# Lambda module for EFS TLS Enforcement                                       #
###############################################################################

module "efs_tls_enforcement_compliance" {
  source      = "../../modules/lambda"
  lambda_name = "efs-tls-enforcement"
  policy_document = templatefile("../../modules/policy-files/efs_tls_compliance.json", {
    region     = data.aws_region.current.name,
    account_id = data.aws_caller_identity.current.account_id
  })
  lambda_script_dir = "../../modules/scripts/efs-tls-enforcement/"
  lambda_handler    = "efs_tls_enforcement.lambda_handler"
  runtime           = "python3.12"
  timeout           = 900
  principal         = "config.amazonaws.com"
}

###############################################################################
# Conformance pack that deploys Config Rules for Lambda-based validation      #
###############################################################################

resource "aws_config_conformance_pack" "lambdarules" {
  name = "Lambdarulesconformancepack"

  template_body = <<EOT
Resources:
  efstlsenforcement:
    Properties:
      ConfigRuleName: efstlsenforcement_${data.aws_caller_identity.current.account_id}
      Scope:
        ComplianceResourceTypes:
          - "AWS::EFS::FileSystem"
      Source:
        Owner: CUSTOM_LAMBDA
        SourceIdentifier: "${module.efs_tls_enforcement_compliance.lambda_arn}"
        SourceDetails:
          - EventSource: "aws.config"
            MessageType: "ConfigurationItemChangeNotification"
      Type: AWS::Config::ConfigRule
EOT

  depends_on = [module.efs_tls_enforcement_compliance]
}
