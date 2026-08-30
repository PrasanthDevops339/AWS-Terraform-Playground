variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Cluster name suffix. The module prefixes it with the account alias"
  type        = string
  default     = "fargate-deploy-types"
}

variable "vpc_id" {
  description = "VPC the services run in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate task ENIs. Needs a NAT or VPC endpoint route for image pulls"
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

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

################################################################################
# IAM
################################################################################

variable "execution_role_arn" {
  description = "Task execution role ARN, used by the ECS agent to pull images and write logs"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN, the identity the application itself runs as"
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

################################################################################
# Load balancer
#
# Supplied as inputs so the example stays focused on ECS deployment behaviour.
# Both target groups must use target_type = "ip" for the awsvpc network mode
# that Fargate requires.
################################################################################

variable "blue_target_group_arn" {
  description = "ARN of the production (blue) target group"
  type        = string
}

variable "green_target_group_arn" {
  description = "ARN of the alternate (green) target group used for traffic shifting"
  type        = string
}




variable "production_listener_rule_arn" {
  description = "ARN of the listener RULE that ECS reweights during native traffic shifting. This is a rule ARN, not a listener ARN"
  type        = string
}


variable "test_listener_rule_arn" {
  description = "Optional test listener rule ARN for ECS-native blue/green validation"
  type        = string
  default     = null
}

################################################################################
# Observability
################################################################################

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified by the per-service CloudWatch alarms"
  type        = list(string)
  default     = []
}

variable "rollback_alarm_names" {
  description = <<-EOT
    CloudWatch alarm names that trigger an automatic deployment rollback.
    These must already exist when the deployment runs. To use the module's own
    alarms, apply once with this empty, then feed back the
    alarm_names_for_rollback output.
  EOT
  type        = list(string)
  default     = []
}

variable "canary_hook_lambda_arn" {
  description = "Optional Lambda ARN invoked as a canary lifecycle hook"
  type        = string
  default     = null
}

variable "canary_hook_role_arn" {
  description = "IAM role ECS assumes to invoke the canary lifecycle hook Lambda"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    Example = "fargate-all-deployment-types"
  }
}
