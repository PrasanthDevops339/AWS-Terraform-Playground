variable "aws_region" {
  description = "AWS region for the example deployment"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "ECS cluster name to create"
  type        = string
  default     = "three-tier-fargate"
}

variable "vpc_id" {
  description = "VPC that hosts the ECS services"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets shared by all three tiers"
  type        = list(string)
}

variable "service_connect_namespace_arn" {
  description = "Existing Cloud Map HTTP namespace ARN used by Service Connect"
  type        = string
}

variable "exec_log_group_name" {
  description = "Existing CloudWatch log group used for ECS Exec"
  type        = string
}

variable "frontend_security_group_id" {
  description = "Security group for the frontend ECS service"
  type        = string
}

variable "api_security_group_id" {
  description = "Security group for the API ECS service"
  type        = string
}

variable "worker_security_group_id" {
  description = "Security group for the worker ECS service"
  type        = string
}

variable "frontend_execution_role_arn" {
  description = "Task execution role ARN for the frontend tier"
  type        = string
}

variable "frontend_task_role_arn" {
  description = "Task role ARN for the frontend tier"
  type        = string
}

variable "api_execution_role_arn" {
  description = "Task execution role ARN for the API tier"
  type        = string
}

variable "api_task_role_arn" {
  description = "Task role ARN for the API tier"
  type        = string
}

variable "worker_execution_role_arn" {
  description = "Task execution role ARN for the worker tier"
  type        = string
}

variable "worker_task_role_arn" {
  description = "Task role ARN for the worker tier"
  type        = string
}

variable "frontend_target_group_arn" {
  description = "Existing target group ARN for the frontend tier"
  type        = string
}

variable "api_blue_target_group_arn" {
  description = "Production target group ARN for the API tier"
  type        = string
}

variable "api_green_target_group_arn" {
  description = "Alternate target group ARN for API canary traffic"
  type        = string
}

variable "api_production_listener_rule_arn" {
  description = "ALB listener rule ARN that routes production traffic to the API"
  type        = string
}

variable "api_ecs_alb_service_role_arn" {
  description = "Infrastructure IAM role ARN that lets ECS shift ALB traffic"
  type        = string
}

variable "frontend_image" {
  description = "Container image for the frontend tier"
  type        = string
}

variable "api_image" {
  description = "Container image for the API tier"
  type        = string
}

variable "worker_image" {
  description = "Container image for the worker tier"
  type        = string
}

variable "api_deployment_alarm_names" {
  description = "Optional CloudWatch alarm names used for API deployment rollback"
  type        = list(string)
  default     = []
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix used by ALB request count autoscaling"
  type        = string
}

variable "api_blue_target_group_arn_suffix" {
  description = "Target group ARN suffix for the API production target group"
  type        = string
}

variable "fargate_ephemeral_storage_kms_key_id" {
  description = "Optional KMS key ID for cluster-level Fargate ephemeral storage encryption"
  type        = string
  default     = null
}

variable "managed_storage_kms_key_id" {
  description = "Optional KMS key ID for other ECS managed storage encryption"
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags applied by the module"
  type        = map(string)
  default = {
    example = "complete"
  }
}
