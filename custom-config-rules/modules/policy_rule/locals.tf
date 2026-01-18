locals {
  policy_file  = file("../../policies/${var.config_rule_name}/${var.config_rule_name}-${var.config_rule_version}.guard")
  account_alias = data.aws_iam_account_alias.current.account_alias
  random_id    = var.random_id != null ? "-${var.random_id}" : ""
}
