resource "aws_config_organization_custom_policy_rule" "main" {
  count = var.organization_rule && var.create_config_rule ? 1 : 0

  name                = var.config_rule_name
  policy_runtime      = "guard-2.x.x"
  policy_text         = local.policy_file
  trigger_types       = var.trigger_types
  description         = var.description
  excluded_accounts   = var.excluded_accounts
  resource_types_scope = var.resource_types_scope
}
