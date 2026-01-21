variable "policy_rules_list" {
  description = "List of policy rules to include in the conformance pack"
  type = list(object({
    config_rule_name     = string
    config_rule_version  = string
    description          = string
    policy_runtime       = optional(string, "guard-2.x.x")
    resource_types_scope = list(string)
  }))
  default = []
}

variable "cpack_name" {
  description = "Name of the conformance pack"
  type        = string
}

variable "random_id" {
  description = "Random ID suffix for resource names"
  type        = string
  default     = null
}
