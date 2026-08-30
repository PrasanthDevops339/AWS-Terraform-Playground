variable "aws_region" {
  description = "AWS region for the example deployment. Also used in the Service Connect sidecar log configuration"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "ECS cluster name to create. The module prefixes it with the account alias"
  type        = string
  default     = "service-connect-tls"
}

variable "vpc_id" {
  description = "VPC the services run in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the task ENIs. Service Connect requires the awsvpc network mode"
  type        = list(string)
}

variable "api_security_group_id" {
  description = "Security group for the api tasks. Must allow inbound from the web tasks on the api container port"
  type        = string
}

variable "web_security_group_id" {
  description = "Security group for the web tasks"
  type        = string
}

################################################################################
# Service Connect
################################################################################

variable "service_connect_namespace_arn" {
  description = "ARN of an existing Cloud Map HTTP namespace. Both services join this mesh"
  type        = string
}

variable "service_connect_log_group_name" {
  description = "CloudWatch log group for the injected Envoy sidecar. Without these logs, mesh failures look like application bugs"
  type        = string
}

################################################################################
# TLS
#
# ECS issues a short-lived certificate per task from AWS Private CA and rotates
# it. The application keeps serving plain HTTP; the sidecar terminates TLS.
################################################################################

variable "private_ca_arn" {
  description = "ARN of the AWS Private CA that issues Service Connect certificates. Must be ACTIVE"
  type        = string
}

variable "service_connect_tls_role_arn" {
  description = <<-EOT
    IAM role ECS assumes to issue certificates from the Private CA.

    Needs acm-pca:IssueCertificate and acm-pca:GetCertificate on the CA (and
    kms:GenerateDataKey on the CMK if one is set), with a trust policy for
    ecs.amazonaws.com.
  EOT
  type        = string
}

variable "service_connect_tls_kms_key_arn" {
  description = "Optional customer-managed KMS key for the generated private keys. Null uses the AWS-managed key"
  type        = string
  default     = null
}

################################################################################
# Workloads
################################################################################

variable "api_image" {
  description = "Container image for the api service"
  type        = string
}

variable "web_image" {
  description = "Container image for the web service"
  type        = string
}

variable "api_container_port" {
  description = "Port the api container listens on. Also the client alias port other services dial"
  type        = number
  default     = 8080
}

variable "web_container_port" {
  description = "Port the web container listens on"
  type        = number
  default     = 3000
}

variable "execution_role_arn" {
  description = "Task execution role ARN, shared by both services"
  type        = string
}

variable "api_task_role_arn" {
  description = "Task role ARN for the api service"
  type        = string
}

variable "web_task_role_arn" {
  description = "Task role ARN for the web service"
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
    example = "service-connect-tls"
  }
}
