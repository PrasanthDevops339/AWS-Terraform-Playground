variable "config_rule_name" {
  description = "Name of the config rule"
  type        = string
}

variable "create" {
  description = "Boolean to control whether any resources should be created"
  type        = bool
  default     = true
}

variable "organization_rule" {
  type    = bool
  default = false
}

variable "description" {
  description = "Description of the rule"
  type        = string
}

variable "resource_types_scope" {
  description = "(Org Rule Only) List of resources types in the scope of the rule"
  type        = list(string)
  default     = []
}

variable "create_config_rule" {
  description = "Boolean to toggle the rule on and off"
  type        = bool
  default     = true
}

variable "lambda_script_dir" {
  description = "File of the lambda python script"
  type        = string
}

variable "trigger_types" {
  description = "List of notification types that trigger the rule to run an evaluation"
  type        = list(string)
  default     = ["ConfigurationItemChangeNotification"]
}

variable "excluded_accounts" {
  description = "(Org Rule Only) List of excluded accounts"
  type        = list(string)
  default     = []
}

variable "resource_id_scope" {
  description = "(Org Rule Only) Identifier of the resource to evaluate"
  type        = string
  default     = ""
}

variable "message_type" {
  description = "Notification types that trigger the rule to run an evaluation"
  type        = string
  default     = "ConfigurationItemChangeNotification"
}

variable "test_events" {
  type = list(object({
    event_name  = string,
    event_value = string
  }))
  default = []
}

variable "additional_policies" {
  type    = list(string)
  default = []
}

variable "random_id" {
  description = "Random ID suffix for pre-dev resource name isolation"
  type        = string
  default     = null
}

# ==========================
# Lambda Configuration
# ==========================

variable "runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler (entry point). Defaults to lambda_function.lambda_handler"
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 900
}

variable "memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 128
}

variable "log_level" {
  description = "Log level for Lambda function (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
}

variable "environment_variables" {
  description = "Additional environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
