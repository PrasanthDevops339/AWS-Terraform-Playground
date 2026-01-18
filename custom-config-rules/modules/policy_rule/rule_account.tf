resource "aws_config_config_rule" "main" {
  count = !var.organization_rule && var.create_config_rule ? 1 : 0

  name        = "${var.config_rule_name}${local.random_id}"
  description = var.description

  scope {
    compliance_resource_types = var.resource_types_scope
  }

  source {
    owner = "CUSTOM_POLICY"

    source_detail {
      message_type = var.message_type
    }

    custom_policy_details {
      policy_runtime = "guard-2.x.x"
      policy_text    = local.policy_file
    }
  }
}
