# ==========================
# Lambda Package variables
# ==========================
variable "lambda_script" {
  description = "(Optional) The script of the lambda function either rendered(as) file(s) or location of the file(py files)"
  type        = string
  default     = null
}

variable "lambda_script_dir" {
  description = "(Optional) The directory of the lambda function and its modules to zip them"
  type        = string
  default     = null
}

# ==========================
# Lambda function variables
# ==========================
variable "create_lambda_function" {
  description = "(Optional) The boolean value to enable the creation of lambda function and the dependent resources"
  type        = bool
  default     = true
}

variable "lambda_name" {
  description = "(Required) The name of the lambda function and all the dependent resources"
  type        = string
}

variable "lambda_description" {
  description = "(Optional) Description of what your Lambda Function does"
  type        = string
  default     = "Serverless lambda function"
}

variable "lambda_role_arn" {
  description = "(Required) The Amazon Resource Name (ARN) of the iam role attached to the lambda"
  type        = string
}

variable "lambda_handler" {
  description = "(Optional) The handler used to trigger script, entry point of lambda function"
  type        = string
  default     = null
}

variable "memory_size" {
  description = "(Optional) Amount of memory in MB your Lambda Function can use at runtime"
  type        = number
  default     = 128
}

variable "reserved_concurrent_executions" {
  description = "The amount of reserved concurrent executions for this Lambda Function. A value of 0 disables Lambda Function from being triggered and -1 removes any concurrency limitations."
  type        = number
  default     = -1
}

variable "runtime" {
  description = "(Optional) The identifier of the function's runtime"
  type        = string
  default     = null
}

variable "layers" {
  description = "(Optional) The list of Lambda Layer Version ARNs (maximum of 5) to attach to your Lambda Function"
  type        = list(any)
  default     = []
}

variable "timeout" {
  description = "(Optional) The amount of time your Lambda Function has to run in seconds"
  type        = number
  default     = 900
}

variable "publish" {
  description = "(Optional) Whether to publish creation/change as new Lambda Function Version"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "(Optional) KMS key ARN to encrypt environment variables"
  type        = string
  default     = null
}

variable "image_uri" {
  description = "(Optional) The ECR image URI containing the function's deployment package."
  type        = string
  default     = null
}

variable "package_type" {
  description = "(Optional) The Lambda deployment package type. Valid options: Zip or Image"
  type        = string
  default     = "zip"
}

variable "lambda_package_path" {
  description = "(Optional) Lambda package zip file will be stored on valid path"
  type        = string
  default     = null
}

variable "upload_to_s3" {
  description = "(Optional) The boolean value to upload the zip file to s3 and pass it to lambda"
  type        = bool
  default     = false
}

variable "lambda_bucket_name" {
  description = "(Optional) The S3 bucket location containing the function's deployment package"
  type        = string
  default     = null
}

variable "lambda_bucket_key" {
  description = "(Optional) The S3 key of an object containing the function's deployment package"
  type        = string
  default     = null
}

variable "lambda_bucket_object_version" {
  description = "(Optional) The object version containing the function's deployment package"
  type        = string
  default     = null
}

variable "ephemeral_storage" {
  description = "(Optional) The amount of ephemeral storage for the lambda to use. Default is 512 MB, maximum is 10240 MB"
  type        = number
  default     = 512
}

variable "create_lambda_permission" {
  description = "True to create lambda permission to get triggered, false to not create permission"
  type        = bool
  default     = true
}

variable "event_source_mapping" {
  description = "Map of event source mapping"
  type = map(object({
    event_source_arn                   = optional(string, null)
    starting_position                  = optional(string, null)
    batch_size                         = optional(number, null)
    metrics_config                     = optional(any, null)
    maximum_batching_window_in_seconds = optional(number, null)
    enabled                            = optional(bool, null)
    kms_key_arn                        = optional(string, null)
    filter_criteria                    = optional(any, null)
  }))
  default = {}
}

variable "tags" {
  description = "Default tag values to be applied to all resources."
  type        = map(string)
  default     = {}
}

variable "allowed_triggers" {
  description = "Map of allowed triggers to create Lambda permissions"
  type        = map(any)
  default     = {}
}

variable "logging_config" {
  description = "map for logging config"
  type        = map(string)
  default     = {}
}

variable "vpc_config" {
  description = "map for VPC config"
  type        = map(any)
  default     = {}
}

variable "environment" {
  description = "Map of environment variables"
  type        = map(string)
  default     = {}
}

variable "image_config" {
  description = "map for image config"
  type        = map(any)
  default     = {}
}

variable "dead_letter_config" {
  description = "map for dead letter config"
  type        = map(any)
  default     = {}
}

variable "tracing_config" {
  description = "map for tracing config"
  type        = map(any)
  default     = {}
}

variable "file_system_config" {
  description = "map for EFS config"
  type        = map(any)
  default     = {}
}

variable "architectures" {
  description = "Instruction set architecture for your Lambda function. Valid values are ["x86_64"] and ["arm64"]."
  type        = list(string)
  default     = null
}

variable "test_events" {
  type = list(object({
    event_name  = string,
    event_value = string
  }))
  default = []
}

variable "package_tags" {
  description = "(Optional) Tags for the uploaded S3 object"
  type        = map(string)
  default     = {}
}
