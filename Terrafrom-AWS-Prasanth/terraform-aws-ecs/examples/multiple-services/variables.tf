variable "aws_region" {
  description = "AWS region for the example deployment"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "ECS cluster name to create. The module prefixes it with the account alias"
  type        = string
  default     = "multi-service"
}

variable "vpc_id" {
  description = "VPC the services run in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the task ENIs, shared by all four services"
  type        = list(string)
}

variable "container_port" {
  description = "Port the load-balanced containers listen on"
  type        = number
  default     = 8080
}

################################################################################
# Per-service security groups
#
# Separate groups are what keep the tiers isolated: the web tier should be
# reachable from the public ALB, the api tier only from the web tier, and the
# workers from neither.
################################################################################

variable "web_security_group_id" {
  description = "Security group for the public web tier task ENIs"
  type        = string
}

variable "api_security_group_id" {
  description = "Security group for the internal api tier task ENIs"
  type        = string
}

variable "worker_security_group_id" {
  description = "Security group for the worker and scheduler task ENIs. No inbound rules needed"
  type        = string
}

################################################################################
# Images
################################################################################

variable "web_image" {
  description = "Container image for the web tier"
  type        = string
}

variable "api_image" {
  description = "Container image for the api tier"
  type        = string
}

variable "worker_image" {
  description = "Container image for the queue worker"
  type        = string
}

variable "scheduler_image" {
  description = "Container image for the singleton scheduler"
  type        = string
}

################################################################################
# Load balancing
################################################################################

variable "web_blue_target_group_arn" {
  description = "Production target group for the web tier, target_type = \"ip\""
  type        = string
}

variable "web_green_target_group_arn" {
  description = "Alternate target group the web tier shifts traffic to during a blue/green deployment"
  type        = string
}

variable "web_production_listener_rule_arn" {
  description = "Listener RULE ARN that ECS reweights for the web tier. A rule ARN, not a listener ARN"
  type        = string
}

variable "api_target_group_arn" {
  description = "Target group for the internal api tier. Rolling deployment, so no alternate group is needed"
  type        = string
}

################################################################################
# Observability
################################################################################

variable "execution_role_arn" {
  description = "Task execution role ARN, shared by all four services"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN, shared by all four services. Split this per service if their permissions differ"
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
    example = "multiple-services"
  }
}
