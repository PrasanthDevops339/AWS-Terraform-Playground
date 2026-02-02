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
  description = "Name of the project"
  type        = string
  default     = "simple-efs-policy-insufficient"
}

variable "vpc_name" {
  description = "Name tag of the VPC to use"
  type        = string
  default     = "ins-dev-vpc-use2"
}

variable "subnet_name_filter" {
  description = "Filter pattern for subnet names (e.g., *-data-* for data subnets)"
  type        = string
  default     = "*-data-*"
}

variable "allowed_cidrs" {
  description = "List of CIDR blocks allowed to access EFS"
  type        = list(string)
  default = [
    "10.0.0.0/16"
  ]
}

variable "enable_backup" {
  description = "Enable EFS backup policy"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
