locals {
  account_alias = data.aws_iam_account_alias.current.account_alias
}

data "aws_iam_account_alias" "current" {}

data "aws_s3_bucket" "bootstrap" {
  bucket = "${data.aws_iam_account_alias.current.id}-bootstrap-use2"
}
