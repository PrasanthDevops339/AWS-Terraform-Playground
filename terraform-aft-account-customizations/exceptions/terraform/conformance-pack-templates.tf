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
  #
  # PERIODIC (ScheduledNotification) trigger:
  # The Lambda enumerates every EFS file system in the account on each run and
  # reports them all in a single batched put_evaluations call for the whole rule.
  # This keeps the conformance pack scored on every cycle - the rule always has a
  # result for every file system instead of showing "no results / insufficient
  # data" while waiting for individual ConfigurationItemChangeNotification events.
  #
  # Scope.ComplianceResourceTypes is intentionally omitted: it only filters which
  # resources trigger a configuration-change rule. A periodic rule runs on a
  # schedule and the Lambda self-enumerates the EFS file systems, so a resource
  # scope is unnecessary (and ComplianceResourceTypes is not valid for a rule whose
  # only trigger is periodic).
  #
  # MaximumExecutionFrequency accepts: One_Hour, Three_Hours, Six_Hours,
  # Twelve_Hours, TwentyFour_Hours. Lower it for faster feedback at higher cost.
  lambda_rules_conformance_pack_template = <<EOT
Resources:
  efstlsenforcement:
    Properties:
      ConfigRuleName: efstlsenforcement_${data.aws_caller_identity.current.account_id}
      Source:
        Owner: CUSTOM_LAMBDA
        SourceIdentifier: "${module.efs_tls_enforcement_compliance.lambda_arn}"
        SourceDetails:
          - EventSource: "aws.config"
            MessageType: "ScheduledNotification"
            MaximumExecutionFrequency: "TwentyFour_Hours"
      Type: AWS::Config::ConfigRule
EOT
}

