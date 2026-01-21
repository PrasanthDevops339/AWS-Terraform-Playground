data "aws_iam_account_alias" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Verify AWS Config recorder exists (should be managed by AFT or Control Tower)
data "aws_config_configuration_recorder" "existing" {
  name = "default"
}
