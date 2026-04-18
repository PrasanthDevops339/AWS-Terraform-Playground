variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-2"
}

variable "image_tag" {
  description = "Docker image tag to deploy across all tiers"
  type        = string
  default     = "latest"
}

variable "account_id" {
  description = "AWS account ID (used for IAM policy resources)"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    env        = "dev"
    managed-by = "terraform"
    project    = "three-tier-ecs"
  }
}
