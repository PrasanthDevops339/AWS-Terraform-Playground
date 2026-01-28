locals {
  cpack_yml = "Resources:\n${local.cpack_blocks}"
  
  # Generate Guard policy rule blocks
  guard_blocks = length(var.policy_rules_list) > 0 ? join("\n", [
    for rule_block in var.policy_rules_list :
    templatefile("${path.module}/templates/guard_template.yml", {
      block_name      = replace("${title(rule_block.config_rule_name)}${local.random_id}", "-", "")
      config_rule_name = "${local.account_alias}-${rule_block.config_rule_name}${local.random_id}"
      policy_runtime  = rule_block.policy_runtime
      description     = rule_block.description
      policy_text     = join("\n", [
        for line in split("\n", trimspace(file("../../policies/${rule_block.config_rule_name}/${rule_block.config_rule_name}-${rule_block.config_rule_version}.guard"))) :
        "          ${line}"
      ])

      resource_types_scope = trimspace(join("", [
        for res_type in rule_block.resource_types_scope :
        "      - ${res_type}\n"
      ]))
    })
  ]) : ""
  
  # Generate Lambda rule blocks
  # Lambda rules enable validation logic that requires:
  # - AWS API calls (data not in Config items)
  # - Complex parsing (JSON policies, nested structures)
  # - Runtime queries to other services
  # Used when Guard policy DSL limitations are reached
  lambda_blocks = length(var.lambda_rules_list) > 0 ? join("\n", [
    for rule_block in var.lambda_rules_list :
    templatefile("${path.module}/templates/lambda_template.yml", {
      block_name          = replace("${title(rule_block.config_rule_name)}${local.random_id}", "-", "")
      config_rule_name    = "${local.account_alias}-${rule_block.config_rule_name}${local.random_id}"
      description         = rule_block.description
      lambda_function_arn = rule_block.lambda_function_arn
      message_type        = rule_block.message_type

      resource_types_scope = trimspace(join("", [
        for res_type in rule_block.resource_types_scope :
        "        - ${res_type}\n"
      ]))
    })
  ]) : ""
  
  # Generate AWS Managed rule blocks
  # AWS Managed rules are pre-built by AWS for common compliance checks
  # Use when AWS provides built-in rule that meets requirements
  managed_blocks = length(var.managed_rules_list) > 0 ? join("\n", [
    for rule_block in var.managed_rules_list :
    templatefile("${path.module}/templates/managed_template.yml", {
      block_name        = replace("${title(rule_block.config_rule_name)}${local.random_id}", "-", "")
      config_rule_name  = "${local.account_alias}-${rule_block.config_rule_name}${local.random_id}"
      description       = rule_block.description
      source_identifier = rule_block.source_identifier
      resource_types_scope = trimspace(join("", [
        for res_type in rule_block.resource_types_scope :
        "        - ${res_type}\n"
      ]))
      input_parameters = length(rule_block.input_parameters) > 0 ? format("InputParameters: %s",
        jsonencode(rule_block.input_parameters)
      ) : ""
    })
  ]) : ""
  
  # Combine all rule blocks (Guard + Lambda + Managed)
  cpack_blocks = trimspace(join("\n", compact([
    local.guard_blocks,
    local.lambda_blocks,
    local.managed_blocks
  ])))
}
