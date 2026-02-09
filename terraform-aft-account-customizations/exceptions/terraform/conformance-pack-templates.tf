###############################################################################
# AWS Config Conformance Pack YAML Templates                                 #
# Purpose: Centralized location for all conformance pack template definitions#
###############################################################################
#
# Why separate file:
#   - Easier to find and edit YAML templates
#   - Separates template definitions from resource configurations
#   - Better organization for multiple conformance packs
#   - Simplifies validation and review process
#
# Usage:
#   Templates defined here can be referenced from any .tf file in this directory
#   Example: local.lambda_rules_conformance_pack_template
#
###############################################################################

###############################################################################
# Lambda-Based Config Rules Conformance Pack Template                        #
###############################################################################

locals {
  # EFS TLS Enforcement Rule Template
  lambda_rules_conformance_pack_template = <<EOT
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
}
