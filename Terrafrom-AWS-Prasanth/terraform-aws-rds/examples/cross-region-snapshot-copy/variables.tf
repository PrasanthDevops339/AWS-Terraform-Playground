################################################################################
# Variables - Cross-Region Automated Backup Replication Example
################################################################################

variable "account_id" {
  description = "AWS Account ID for IAM role permissions"
  type        = string
}

variable "name" {
  description = "Name to be used on all resources as identifier"
  type        = string
  default     = "oracle-cross-region"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "primary_region" {
  description = "AWS region for the primary RDS instance"
  type        = string
  default     = "us-east-2"
}

variable "secondary_region" {
  description = "AWS region for backup replication destination"
  type        = string
  default     = "us-east-1"
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    Owner       = "platform-team"
    Environment = "dev"
    Project     = "oracle-cross-region-backup"
    ManagedBy   = "terraform"
  }
}