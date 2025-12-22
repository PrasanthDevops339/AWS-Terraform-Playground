# Variables for Blue/Green Deployment Example

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "webapp-bg"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "container_image" {
  description = "Container image for the web application"
  type        = string
  default     = "nginx:latest"
}

variable "app_version" {
  description = "Application version"
  type        = string
  default     = "1.0.0"
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto scaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto scaling"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment    = "production"
    DeploymentType = "blue-green"
    ManagedBy      = "terraform"
  }
}