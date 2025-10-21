# Parameter Group
resource "aws_db_parameter_group" "main" {
  count       = var.db_parameter_group_name == null ? 1 : 0
  name        = "${local.account_alias}-${var.identifier}"
  description = coalesce(var.parameter_group_description, "Database parameter group for ${var.identifier}")
  family      = var.family

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", null)
    }
  }

  tags = merge(var.tags, { Name = "${local.account_alias}-${var.identifier}" })

  lifecycle { create_before_destroy = true }
}
