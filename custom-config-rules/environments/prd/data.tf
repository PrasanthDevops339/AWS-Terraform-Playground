locals {
  region        = data.aws_region.current.name
  account_alias = data.aws_iam_account_alias.current.account_alias
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_iam_account_alias" "current" {}
