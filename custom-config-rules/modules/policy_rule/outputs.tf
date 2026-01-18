output "rule_id" {
  value = !var.organization_rule ? aws_config_config_rule.main[0].id : null
}
