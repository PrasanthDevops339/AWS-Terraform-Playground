variable "aws_region" {
  description = "AWS region for the example deployment"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "ECS cluster name to create. The module prefixes it with the account alias"
  type        = string
  default     = "blue-green"
}

variable "vpc_id" {
  description = "VPC the service runs in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the task ENIs"
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

################################################################################
# Traffic shifting
#
# Both target groups must use target_type = "ip", because Fargate and the
# awsvpc network mode register task ENIs rather than instances.
################################################################################

variable "blue_target_group_arn" {
  description = "ARN of the target group currently serving production traffic"
  type        = string
}

variable "green_target_group_arn" {
  description = "ARN of the alternate target group ECS shifts traffic to"
  type        = string
}

variable "production_listener_rule_arn" {
  description = "ARN of the listener RULE whose weights ECS rewrites. A rule ARN, not a listener ARN"
  type        = string
}

variable "test_listener_rule_arn" {
  description = "Optional listener rule ARN for routing test traffic to green before the production cut"
  type        = string
  default     = null
}

variable "rollback_alarm_names" {
  description = "CloudWatch alarm names that trigger an automatic rollback mid-deployment. Must already exist when the deployment runs"
  type        = list(string)
  default     = []
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
    example = "blue-green-deployment"
  }
}
