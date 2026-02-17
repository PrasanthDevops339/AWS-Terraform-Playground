variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project — used in resource names and tags"
  type        = string
  default     = "simple-sqs"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
