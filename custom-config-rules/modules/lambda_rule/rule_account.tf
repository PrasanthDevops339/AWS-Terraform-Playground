
resource "aws_config_config_rule" "main" {
  count = (!var.organization_rule && var.create_config_rule) ? 1 : 0

  name        = var.random_id != null ? "${var.config_rule_name}-${var.random_id}" : var.config_rule_name
  description = var.description

  scope {
    compliance_resource_types = var.resource_types_scope
  }

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = module.lambda.lambda_arn

    source_detail {
      message_type = var.message_type
    }
  }

  depends_on = [
    aws_lambda_permission.lambda_perm
  ]
}
