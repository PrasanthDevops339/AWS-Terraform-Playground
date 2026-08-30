variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Cluster name suffix. The module prefixes it with the account alias"
  type        = string
  default     = "ec2-deploy-types"
}

variable "vpc_id" {
  description = "VPC the cluster and its container instances run in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the container instances and for awsvpc task ENIs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group of the ALB. Allowed inbound to the container instances"
  type        = string
}

variable "service_security_group_id" {
  description = "Security group applied to awsvpc task ENIs. Not used by bridge or host services, which share the instance security group"
  type        = string
}

variable "container_image" {
  description = "Application container image"
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
}

variable "log_agent_image" {
  description = "Image for the DAEMON log agent"
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
}

variable "container_port" {
  description = "Port the application container listens on"
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
# EC2 needs BOTH target group flavours, which is the main wiring difference
# from Fargate:
#
#   target_type = "instance"  for bridge and host network modes
#   target_type = "ip"        for the awsvpc network mode
################################################################################

variable "instance_blue_target_group_arn" {
  description = "ARN of an instance-type target group, used by the bridge-mode service"
  type        = string
}

variable "ip_blue_target_group_arn" {
  description = "ARN of the production ip-type target group, used by the awsvpc services"
  type        = string
}

variable "ip_green_target_group_arn" {
  description = "ARN of the alternate ip-type target group used for traffic shifting"
  type        = string
}




variable "production_listener_rule_arn" {
  description = "ARN of the listener RULE that ECS reweights during native traffic shifting"
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
  description = "CloudWatch alarm names that trigger an automatic deployment rollback. Must already exist when the deployment runs"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    Example = "ec2-all-deployment-types"
  }
}
