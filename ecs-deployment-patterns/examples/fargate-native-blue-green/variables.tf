variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Cluster name suffix. The module prefixes it with the account alias"
  type        = string
  default     = "ecs-native"
}

variable "vpc_id" {
  description = "VPC the load balancer and tasks run in"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR, used to scope ALB egress to the tasks"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets for the Application Load Balancer"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate task ENIs. Needs a NAT or VPC endpoint route for image pulls"
  type        = list(string)
}

variable "ingress_cidr" {
  description = "CIDR allowed to reach the production listener on port 80"
  type        = string
}

variable "test_ingress_cidr" {
  description = "CIDR allowed to reach the test listener on port 8080. Keep this narrower than ingress_cidr - it serves the not-yet-promoted version"
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

variable "health_check_path" {
  description = "Target group health check path"
  type        = string
  default     = "/"
}

variable "execution_role_arn" {
  description = "Task execution role ARN, used by the ECS agent to pull images and write logs"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN, the identity the application itself runs as"
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
    Example = "fargate-native-blue-green"
  }
}
