resource "aws_config_organization_custom_rule" "main" {
  count = (var.organization_rule && var.create_config_rule) ? 1 : 0

  name = var.config_rule_name

  lambda_function_arn = module.lambda.lambda_arn
  trigger_types       = var.trigger_types
  excluded_accounts   = var.excluded_accounts

  resource_types_scope = var.resource_types_scope
  resource_id_scope    = var.resource_id_scope

  depends_on = [
    aws_lambda_permission.lambda_perm
  ]
}
