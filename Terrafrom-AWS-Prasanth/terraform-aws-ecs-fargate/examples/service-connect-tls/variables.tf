# Variables for Service Connect with TLS Example

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "secure-microservices"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "service_connect_namespace" {
  description = "Service Connect namespace"
  type        = string
  default     = "secure.local"
}

# Certificate Authority Variables
variable "ca_common_name" {
  description = "Common name for the Certificate Authority"
  type        = string
  default     = "Service Connect CA"
}

variable "ca_country" {
  description = "Country for the Certificate Authority"
  type        = string
  default     = "US"
}

variable "ca_state" {
  description = "State for the Certificate Authority"
  type        = string
  default     = "Washington"
}

variable "ca_locality" {
  description = "Locality for the Certificate Authority"
  type        = string
  default     = "Seattle"
}

variable "ca_organization" {
  description = "Organization for the Certificate Authority"
  type        = string
  default     = "My Company"
}

variable "ca_organizational_unit" {
  description = "Organizational unit for the Certificate Authority"
  type        = string
  default     = "IT Department"
}

variable "ca_deletion_days" {
  description = "Days before permanent deletion of CA"
  type        = number
  default     = 7
}

# API Service Variables
variable "api_image" {
  description = "Container image for the API service"
  type        = string
  default     = "nginx:alpine"
}

variable "api_version" {
  description = "API service version"
  type        = string
  default     = "1.0.0"
}

variable "api_cpu" {
  description = "CPU units for API service"
  type        = number
  default     = 512
}

variable "api_memory" {
  description = "Memory for API service"
  type        = number
  default     = 1024
}

variable "api_port" {
  description = "Port for API service"
  type        = number
  default     = 8443
}

variable "api_desired_count" {
  description = "Desired count for API service"
  type        = number
  default     = 2
}

variable "api_min_capacity" {
  description = "Minimum capacity for API service auto scaling"
  type        = number
  default     = 1
}

variable "api_max_capacity" {
  description = "Maximum capacity for API service auto scaling"
  type        = number
  default     = 10
}

# Client Service Variables
variable "client_image" {
  description = "Container image for the client service"
  type        = string
  default     = "alpine:latest"
}

variable "client_version" {
  description = "Client service version"
  type        = string
  default     = "1.0.0"
}

variable "client_cpu" {
  description = "CPU units for client service"
  type        = number
  default     = 256
}

variable "client_memory" {
  description = "Memory for client service"
  type        = number
  default     = 512
}

variable "client_port" {
  description = "Port for client service"
  type        = number
  default     = 80
}

variable "client_desired_count" {
  description = "Desired count for client service"
  type        = number
  default     = 1
}

variable "client_min_capacity" {
  description = "Minimum capacity for client service auto scaling"
  type        = number
  default     = 1
}

variable "client_max_capacity" {
  description = "Maximum capacity for client service auto scaling"
  type        = number
  default     = 5
}

# Database Service Variables
variable "db_image" {
  description = "Container image for the database service"
  type        = string
  default     = "postgres:13-alpine"
}

variable "db_cpu" {
  description = "CPU units for database service"
  type        = number
  default     = 512
}

variable "db_memory" {
  description = "Memory for database service"
  type        = number
  default     = 1024
}

variable "db_port" {
  description = "Port for database service"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
  default     = "ChangeMeInProduction!"
}

# TLS Configuration
variable "tls_idle_timeout" {
  description = "TLS idle timeout in seconds"
  type        = number
  default     = 60
}

variable "tls_request_timeout" {
  description = "TLS per-request timeout in seconds"
  type        = number
  default     = 30
}

# Logging
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "production"
    Security    = "tls-enabled"
    ManagedBy   = "terraform"
  }
}