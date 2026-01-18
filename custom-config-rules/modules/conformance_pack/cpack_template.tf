locals {
  cpack_yml = "Resources:\n${local.cpack_blocks}"
  # I promise this isn't scary
  cpack_blocks = join("\n", [
    # Loop through all of the rules and generate strings from templates
    for rule_block in var.policy_rules_list :
    templatefile("${path.module}/templates/guard_template.yml", {
      block_name      = replace("${title(rule_block.config_rule_name)}${local.random_id}", "-", "")
      config_rule_name = "${local.account_alias}-${rule_block.config_rule_name}${local.random_id}"
      policy_runtime  = rule_block.policy_runtime
      description     = rule_block.description
      policy_text     = replace(trimspace(file("../../policies/${rule_block.config_rule_name}/${rule_block.config_rule_name}-${rule_block.config_rule_version}.guard")), "\n", "")

      # Build out a list of strings to set within the template
      resource_types_scope = trimspace(join("", [
        for res_type in rule_block.resource_types_scope :
        "      - ${res_type}\n"
      ]))
    })
  ])
}
