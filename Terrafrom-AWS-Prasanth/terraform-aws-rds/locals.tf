locals {
  account_alias = data.aws_iam_account_alias.current.account_alias
  password      = !var.manage_master_user_password ? join("", random_string.password.*.result) : null

  db_option_group_name    = var.db_option_group_name == null ? join("", aws_db_option_group.main.*.name) : var.db_option_group_name
  db_subnet_group_name    = var.db_subnet_group_name == null ? join("", aws_db_subnet_group.main.*.name) : var.db_subnet_group_name
  db_parameter_group_name = var.db_parameter_group_name == null ? join("", aws_db_parameter_group.main.*.name) : var.db_parameter_group_name

  final_snapshot_identifier = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${local.account_alias}-${var.identifier}-${try(random_id.snapshot_identifier[0].hex, "")}")

  is_replica_local = var.replicate_source_db != null
}
