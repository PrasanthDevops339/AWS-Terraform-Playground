locals {
  account_alias = data.aws_iam_account_alias.current.account_alias
  random_id     = var.random_id != null ? "-${var.random_id}" : ""
  
  # Generate the conformance pack YAML template
  cpack_yml = "Resources:\n${local.cpack_blocks}"
  
  # Build YAML blocks for each policy rule
  cpack_blocks = join("\n", [
    for rule_block in var.policy_rules_list :
    templatefile("${path.module}/templates/guard_template.yml", {
      block_name           = replace("${title(rule_block.config_rule_name)}${local.random_id}", "-", "")
      config_rule_name     = "${local.account_alias}-${rule_block.config_rule_name}${local.random_id}"
      policy_runtime       = rule_block.policy_runtime
      description          = rule_block.description
      policy_text          = replace(trimspace(file("../../policies/${rule_block.config_rule_name}/${rule_block.config_rule_name}-${rule_block.config_rule_version}.guard")), "\n", "")
      resource_types_scope = trimspace(join("", [
        for res_type in rule_block.resource_types_scope :
        "      - ${res_type}\n"
      ]))
    })
  ])
}
