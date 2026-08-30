variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Cluster name suffix. The module prefixes it with the account alias"
  type        = string
  default     = "mixed-capacity"
}

variable "vpc_id" {
  description = "VPC the cluster, container instances and tasks run in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for container instances and awsvpc task ENIs"
  type        = list(string)
}

variable "service_security_group_id" {
  description = "Security group applied to awsvpc task ENIs"
  type        = string
}

variable "container_port" {
  description = "Port the API container listens on"
  type        = number
  default     = 8080
}

variable "api_image" {
  description = "Image for the Fargate API service"
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
}

variable "inference_image" {
  description = "Image for the GPU inference service"
  type        = string
}

variable "batch_image" {
  description = "Image for the Spot batch service"
  type        = string
}

variable "node_agent_image" {
  description = "Image for the DAEMON node agent"
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
}

variable "execution_role_arn" {
  description = "Task execution role ARN, used by the ECS agent to pull images and write logs"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN, the identity the applications run as"
  type        = string
}

variable "ecs_alb_service_role_arn" {
  description = <<-EOT
    Optional. IAM role ECS assumes to reweight ALB listener rules during
    BLUE_GREEN, LINEAR and CANARY deployments.

    Leave null and the module creates one per traffic-shifting service, with
    AmazonECSInfrastructureRolePolicyForLoadBalancers attached. Set it only to
    reuse a role you already manage.
  EOT
  type        = string
  default     = null
}

variable "blue_target_group_arn" {
  description = "ARN of the production ip-type target group for the API"
  type        = string
}

variable "green_target_group_arn" {
  description = "ARN of the alternate ip-type target group for the API"
  type        = string
}

variable "production_listener_rule_arn" {
  description = "ARN of the listener RULE that ECS reweights during traffic shifting"
  type        = string
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
    Example = "mixed-fargate-ec2"
  }
}
