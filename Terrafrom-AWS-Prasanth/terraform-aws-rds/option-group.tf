# Option Group (engines that support it)
resource "aws_db_option_group" "main" {
  count                    = var.db_option_group_name == null ? 1 : 0
  name                     = "${local.account_alias}-${var.identifier}"
  engine_name              = var.engine
  major_engine_version     = var.major_engine_version
  option_group_description = coalesce(var.option_group_description, "Option group for ${var.identifier}")

  dynamic "option" {
    for_each = var.options
    content {
      option_name                    = option.value.option_name
      port                           = lookup(option.value, "port", null)
      version                        = lookup(option.value, "version", null)
      vpc_security_group_memberships = lookup(option.value, "vpc_security_group_memberships", null)
    }
  }

  dynamic "option_settings" {
    for_each = lookup(var.option_settings, "values", null) == null ? [] : var.option_settings.values
    content {
      name  = lookup(option_settings.value, "name", null)
      value = lookup(option_settings.value, "value", null)
    }
  }

  tags = merge(var.tags, { Name = "${local.account_alias}-${var.identifier}" })

  timeouts {
    delete = lookup(var.option_group_timeouts, "delete", null)
  }

  lifecycle { create_before_destroy = true }
}
