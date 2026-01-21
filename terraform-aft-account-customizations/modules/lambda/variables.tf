
variable "workspace" {
  type        = string
  description = "Workspace suffix used for naming. Use 'none' to omit."
  default     = "none"
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to resources."
  default     = {}
}

variable "create_lambda_function" {
  type        = bool
  description = "Whether to create the Lambda function."
  default     = true
}

variable "lambda_name" {
  type        = string
  description = "Logical lambda name (used in naming and packaging)."
}

variable "lambda_description" {
  type        = string
  description = "Lambda description."
  default     = null
}

variable "lambda_handler" {
  type        = string
  description = "Handler override (zip-based). If null and image_uri is null, defaults to '<lambda_name>.lambda_handler'."
  default     = null
}

variable "runtime" {
  type        = string
  description = "Lambda runtime (zip-based)."
  default     = "python3.12"
}

variable "memory_size" {
  type    = number
  default = 128
}

variable "reserved_concurrent_executions" {
  type    = number
  default = -1
}

variable "timeout" {
  type    = number
  default = 60
}

variable "ephemeral_storage" {
  type    = number
  default = 512
}

variable "layers" {
  type    = list(string)
  default = []
}

variable "publish" {
  type    = bool
  default = false
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for env var encryption + log group + S3 object (if used)."
  default     = null
}

variable "package_type" {
  type        = string
  description = "Zip or Image."
  default     = "Zip"
}

variable "image_uri" {
  type        = string
  description = "ECR image URI for image-based Lambda. If set, zip packaging is skipped."
  default     = null
}

variable "source_dir" {
  type        = string
  description = "Directory containing the lambda source to zip (zip-based)."
  default     = null
}

variable "upload_to_s3" {
  type        = bool
  description = "Upload zip to S3 and reference it from Lambda."
  default     = false
}

variable "lambda_bucket_name" {
  type        = string
  description = "S3 bucket name to store lambda packages when upload_to_s3=true."
  default     = null
}

variable "lambda_bucket_object_version" {
  type        = string
  description = "Optional S3 object version for the uploaded zip."
  default     = null
}

# IAM
variable "lambda_role_arn" {
  type        = string
  description = "Existing role ARN. If null, module creates one."
  default     = null
}

variable "assume_role_policy" {
  type        = string
  description = "Override assume role policy JSON; empty string means build internally."
  default     = ""
}

variable "boundary_permissions_policy" {
  type        = string
  description = "Permissions boundary ARN for created role."
  default     = null
}

variable "policy_document" {
  type        = string
  description = "Inline IAM policy JSON for the lambda role."
  default     = "{}"
}

# Logging
variable "lambda_logs_retention_period" {
  type    = number
  default = 30
}

variable "use_custom_log_group" {
  type    = bool
  default = false
}

variable "log_group_name" {
  type    = string
  default = null
}

variable "log_format" {
  type    = string
  default = "JSON"
}

variable "system_log_level" {
  type    = string
  default = "INFO"
}

# Triggers - CloudWatch Events
variable "create_cloudwatch_event_trigger" {
  type    = bool
  default = false
}

variable "cloudwatch_event_description" {
  type    = string
  default = null
}

variable "schedule_expression" {
  type    = string
  default = null
}

variable "event_pattern" {
  type    = string
  default = null
}

variable "cloudwatch_role_arn" {
  type    = string
  default = null
}

variable "enable_cloudwatch_event" {
  type        = string
  description = "ENABLED or DISABLED"
  default     = "ENABLED"
}

# Triggers - S3
variable "create_bucket_event_trigger" {
  type    = bool
  default = false
}

variable "lambda_trigger_bucket_name" {
  type    = string
  default = null
}

variable "lambda_trigger_bucket_arn" {
  type    = string
  default = null
}

variable "lambda_trigger_bucket_events" {
  type    = list(string)
  default = []
}

variable "lambda_trigger_bucket_object_prefix" {
  type    = string
  default = null
}

variable "lambda_trigger_bucket_object_suffix" {
  type    = string
  default = null
}

# Triggers - SNS
variable "create_sns_event_trigger" {
  type    = bool
  default = false
}

variable "lambda_trigger_sns_topic_arn" {
  type        = string
  description = "If provided, uses existing SNS topic. If null, module creates one."
  default     = null
}

variable "lambda_trigger_sns_topic_policy" {
  type        = string
  description = "SNS topic policy JSON (only used if module creates topic)."
  default     = null
}

# Lambda permission passthrough (generic)
variable "create_lambda_permission" {
  type    = bool
  default = false
}

variable "statement_id" {
  type    = string
  default = "AllowExecution"
}

variable "action" {
  type    = string
  default = "lambda:InvokeFunction"
}

variable "principal" {
  type    = string
  default = null
}

variable "source_arn" {
  type    = string
  default = null
}

# Env/VPC/Image extras
variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "vpc_subnet_ids" {
  type    = list(string)
  default = null
}

variable "vpc_security_group_ids" {
  type    = list(string)
  default = null
}

variable "image_config_entry_point" {
  type    = list(string)
  default = []
}

variable "image_config_command" {
  type    = list(string)
  default = []
}

variable "image_config_working_directory" {
  type    = string
  default = null
}

variable "dead_letter_target_arn" {
  type    = string
  default = null
}

variable "tracing_mode" {
  type        = string
  description = "Active or PassThrough"
  default     = null
}

variable "file_system_arn" {
  type    = string
  default = null
}

variable "file_system_local_mount_path" {
  type    = string
  default = null
}
