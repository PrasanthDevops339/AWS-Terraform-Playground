data "aws_iam_account_alias" "current" {}

data "aws_iam_role" "example" {
  name = "${data.aws_iam_account_alias.current.account_alias}-platformadministrator-role"
}
