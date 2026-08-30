variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Cluster name suffix. The module prefixes it with the account alias"
  type        = string
  default     = "ecs-minimal"
}

variable "vpc_id" {
  description = "VPC the service runs in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the task ENIs. Needs a NAT or VPC endpoint route for image pulls"
  type        = list(string)
}

variable "service_security_group_id" {
  description = "Security group applied to the task ENIs"
  type        = string
}

variable "container_image" {
  description = "Container image to run"
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
}

variable "execution_role_arn" {
  description = "Task execution role ARN, used by the ECS agent to pull images and write logs"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN, the identity the application itself runs as"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    Example = "minimal-fargate"
  }
}
