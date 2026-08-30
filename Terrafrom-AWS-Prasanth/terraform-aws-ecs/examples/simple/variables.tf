variable "aws_region" {
  description = "AWS region for the example deployment"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "ECS cluster name to create"
  type        = string
  default     = "simple-fargate"
}

variable "vpc_id" {
  description = "VPC that hosts the ECS service"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the Fargate service"
  type        = list(string)
}

variable "service_security_group_id" {
  description = "Existing security group attached to the ECS service"
  type        = string
}

variable "execution_role_arn" {
  description = "Task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN"
  type        = string
}

variable "target_group_arn" {
  description = "Existing ALB or NLB target group ARN"
  type        = string
}

variable "container_image" {
  description = "Container image URI to deploy"
  type        = string
}

variable "log_group_name" {
  description = "Existing CloudWatch log group used by the container"
  type        = string
}

variable "environment" {
  description = "Environment tag or container environment value"
  type        = string
  default     = "dev"
}

variable "container_port" {
  description = "Application port exposed by the container"
  type        = number
  default     = 8080
}

variable "tags" {
  description = "Common tags applied by the module"
  type        = map(string)
  default = {
    example = "simple"
  }
}
