variable "aws_region" {
  description = "AWS region for the example deployment"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "ECS cluster name to create. The module prefixes it with the account alias"
  type        = string
  default     = "external-deploy"
}

variable "vpc_id" {
  description = "VPC the service runs in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the task ENIs. Set on the task set, not the service"
  type        = list(string)
}

variable "service_security_group_id" {
  description = "Security group applied to the task ENIs"
  type        = string
}

variable "container_image" {
  description = "Container image to run"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "log_group_name" {
  description = "Existing CloudWatch log group for the task"
  type        = string
}

variable "execution_role_arn" {
  description = "Task execution role ARN, used by the ECS agent to pull images and write logs"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN, the identity the application itself runs as"
  type        = string
}

variable "desired_count" {
  description = "Total desired count across all task sets. The module ignores drift on it, since the external system owns it"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Application Auto Scaling floor for the service desired count"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Application Auto Scaling ceiling for the service desired count"
  type        = number
  default     = 10
}

variable "create_initial_task_set" {
  description = "Whether to create a bootstrap task set. Set false when the external deployment system creates all task sets itself"
  type        = bool
  default     = true
}

variable "target_group_arn" {
  description = "Optional target group ARN (target_type = \"ip\") attached to the task set. Null for a service with no load balancer"
  type        = string
  default     = null
}

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified by the per-service CloudWatch alarms"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    example = "external-deployment"
  }
}
