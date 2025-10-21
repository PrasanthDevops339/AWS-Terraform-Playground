# DB Instance - Subnet Group
resource "aws_db_subnet_group" "main" {
  count       = var.create_subnet_group && var.db_subnet_group_name == null ? 1 : 0
  name        = "${local.account_alias}-${var.identifier}"
  description = "Subnet group for ${var.identifier} database instance"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = "${local.account_alias}-${var.identifier}" })
}
