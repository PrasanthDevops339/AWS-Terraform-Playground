# store generated/random password in Secrets Manager (when module manages it)
resource "aws_secretsmanager_secret" "db_password" {
  count                   = !var.manage_master_user_password && !var.is_replica ? 1 : 0
  name                    = "${local.account_alias}-${var.identifier}-rds-password"
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "db_password" {
  count         = !var.manage_master_user_password && !var.is_replica ? 1 : 0
  secret_id     = aws_secretsmanager_secret.db_password[0].id
  secret_string = local.password
}
