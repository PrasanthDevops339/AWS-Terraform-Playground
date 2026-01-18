variable "config_rule_name" {
  description = "Name of the config rule"
  type        = string
}

variable "config_rule_version" {
  description = "Calendar version of the config rule you want to deploy"
  type        = string
}

variable "trigger_types" {
  description = "List of notification types that trigger the rule to run an evaluation"
  type        = list(string)
  default     = ["ConfigurationItemChangeNotification"]
}

variable "message_type" {
  description = "Notification types that trigger the rule to run an evaluation"
  type        = string
  default     = "ConfigurationItemChangeNotification"
}

variable "create_config_rule" {
  description = "Boolean to toggle the rule on and off"
  type        = bool
  default     = true
}

variable "description" {
  description = "Description of the rule"
  type        = string
}

variable "excluded_accounts" {
  description = "List of excluded accounts"
  type        = list(string)
  default     = []
}

variable "resource_types_scope" {
  description = "List of resources types in the scope of the rule"
  type        = list(string)
  default     = []
}

variable "organization_rule" {
  type    = bool
  default = false
}

variable "random_id" {
  description = "Pass in the random id here to append to resource that is created."
  type        = string
  default     = null
}
