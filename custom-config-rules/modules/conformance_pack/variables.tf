variable "policy_rules_list" {
  description = "List of resources types in the scope of the rule"
  type = list(object({
    config_rule_name    = string,
    config_rule_version = string
    description         = string
    policy_runtime      = optional(string, "guard-2.x.x")
    resource_types_scope = list(string)
  }))
  default = []
}

variable "lambda_rules_list" {
  description = "List of Lambda-based custom config rules to include in the conformance pack"
  type = list(object({
    config_rule_name     = string
    description          = string
    lambda_function_arn  = string
    resource_types_scope = list(string)
    message_type         = optional(string, "ConfigurationItemChangeNotification")
  }))
  default = []
}

variable "managed_rules_list" {
  description = "List of AWS managed config rules to include in the conformance pack"
  type = list(object({
    config_rule_name     = string
    description          = string
    source_identifier    = string
    resource_types_scope = list(string)
    input_parameters     = optional(map(string), {})
  }))
  default = []
}

variable "cpack_name" {
  description = "Name of the conformance pack"
  type        = string
}

variable "excluded_accounts" {
  description = "List of excluded accounts that the pack will not deploy to in the organization"
  type        = list(string)
  default     = []
}

variable "organization_pack" {
  description = "Set to true if you want this conformance pack to be deployed across the organization."
  type        = bool
  default     = false
}

variable "random_id" {
  description = "Pass in the random id here to append to resource that is created."
  type        = string
  default     = null
}
