data "aws_iam_account_alias" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Existing, externally owned log group the Lambda writes to. The plan fails
# here if it does not exist in this account and region.
data "aws_cloudwatch_log_group" "app" {
  name = var.app_log_group_name
}
