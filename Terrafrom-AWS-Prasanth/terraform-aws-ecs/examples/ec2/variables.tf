variable "aws_region" {
  description = "AWS region for the example deployment"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Cluster name suffix. The module prefixes it with the account alias"
  type        = string
  default     = "ec2"
}

variable "vpc_id" {
  description = "VPC the container instances and load balancer run in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the container instances. Needs a NAT or VPC endpoint route so the ECS agent can reach ECS and ECR"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group of the Application Load Balancer, allowed inbound to the container instances"
  type        = string
}

variable "instance_type" {
  description = "Container instance type"
  type        = string
  default     = "t3.medium"
}

variable "min_size" {
  description = "Minimum container instances in the Auto Scaling group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum container instances in the Auto Scaling group"
  type        = number
  default     = 6
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

variable "target_group_arn" {
  description = "ARN of an existing target group with target_type = \"instance\". The bridge network mode registers container instances, not task IPs"
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

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified by the per-service CloudWatch alarms"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    example = "ec2"
  }
}
