variable "account_id" {
  default = ""
  type    = string
}

variable "name" {
  description = "event name"
  type        = string
  default     = "simple-lambda-scheduler"
}

variable "description" {
  description = "event description"
  type        = string
  default     = "Schedule trigger for simple lambda function"
}

variable "type" {
  description = "event type"
  type        = string
  default     = "lambda_cron"
}

variable "schedule" {
  description = "cron schedule"
  type        = string
  default     = "cron(0 0 * * ? *)"
}

variable "target" {
  type        = map(string)
  description = "event target arn"
  default = {
    name = ""
    arn  = ""
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, prd, etc)"
  default     = ""
}

variable "account_profile" {
  type        = string
  description = "AWS account profile name"
  default     = ""
}

variable "python_lambda_layer_runtime" {
  type        = string
  description = "Runtime for python lambda functions and layers for this project"
  default     = "python3.12" #required to support pysnow
}

##Bob Added This for just the OTEL testing
variable "otel_python_lambda_layer_runtime" {
  type        = string
  description = "Runtime for python lambda functions and layers for this project"
  default     = "python3.12" #required to support pysnow
}

variable "database_rw_user" {
  description = "The read write uer that will access the RDS database"
  default     = "ccopsrw"
}

variable "region" {
  description = "aws region"
  type        = string
  default     = ""
}

variable "ServiceNowSecret" {
  description = "Service now dev API secret"
  type        = string
  default     = ""
}

variable "ObsrvLambdaToken" {
  description = "Splunk Observability Lambda Token"
  type        = string
  default     = "REDACTED"
}
