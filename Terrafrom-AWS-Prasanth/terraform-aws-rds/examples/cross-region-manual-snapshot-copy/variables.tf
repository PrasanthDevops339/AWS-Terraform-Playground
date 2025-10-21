################################################################################
# Variables - Automated Cross-Region RDS Backup using Lambda and EventBridge
# Following Terraform and AWS Well-Architected Framework Best Practices
################################################################################

#------------------------------------------------------------------------------
# REQUIRED VARIABLES
#------------------------------------------------------------------------------

variable "account_id" {
  description = "AWS Account ID for IAM role permissions and resource access"
  type        = string
}

#------------------------------------------------------------------------------
# NAMING AND IDENTIFICATION
#------------------------------------------------------------------------------

variable "name" {
  description = "Name prefix for all resources (follows AWS naming conventions)"
  type        = string
  default     = "oracle-cross-region"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

#------------------------------------------------------------------------------
# REGIONAL CONFIGURATION
#------------------------------------------------------------------------------

variable "primary_region" {
  description = "AWS region for the primary RDS instance and snapshots"
  type        = string
  default     = "us-east-2"
}

variable "secondary_region" {
  description = "AWS region for cross-region snapshot copies and disaster recovery"
  type        = string
  default     = "us-east-1"
}

#------------------------------------------------------------------------------
# BACKUP AND DISASTER RECOVERY CONFIGURATION
#------------------------------------------------------------------------------

variable "backup_retention_period" {
  description = "Automated backup retention period in days (REMEDIATION: optimized for cost)"
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 7
    error_message = "Backup retention period must be between 1 and 7 days for cost optimization."
  }
}

variable "backup_window" {
  description = "Preferred backup window (UTC) for automated backups"
  type        = string
  default     = "03:00-06:00"

  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]-([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in HH:MM-HH:MM format (UTC)."
  }
}

variable "maintenance_window" {
  description = "Preferred maintenance window for updates and patches"
  type        = string
  default     = "Sun:03:00-Sun:06:00"

  validation {
    condition     = can(regex("^(Mon|Tue|Wed|Thu|Fri|Sat|Sun):[0-2][0-9]:[0-5][0-9]-(Mon|Tue|Wed|Thu|Fri|Sat|Sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "Maintenance window must be in ddd:HH:MM-ddd:HH:MM format."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds for snapshot operations"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "snapshot_retention_days" {
  description = "Number of days to retain cross-region snapshots before deletion"
  type        = number
  default     = 7

  validation {
    condition     = var.snapshot_retention_days >= 1 && var.snapshot_retention_days <= 35
    error_message = "Snapshot retention must be between 1 and 35 days."
  }
}

variable "lambda_schedule" {
  description = "EventBridge schedule expression for automated backups (e.g., rate(1 hour) or cron(0 2 * * ? *))"
  type        = string
  default     = "rate(6 hours)"
}



#------------------------------------------------------------------------------
# NETWORKING AND SECURITY CONFIGURATION
#------------------------------------------------------------------------------

variable "primary_vpc_name" {
  description = "Name tag of the VPC in primary region for RDS deployment"
  type        = string
  default     = "erieins-dev-vpc-use2"
}

variable "secondary_vpc_name" {
  description = "Name tag of the VPC in secondary region for disaster recovery"
  type        = string
  default     = "erieins-dev-vpc-use1"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instances (recommended for production)"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# TAGGING STRATEGY (AWS WELL-ARCHITECTED FRAMEWORK)
#------------------------------------------------------------------------------

variable "tags" {
  description = "Common tags to apply to all resources (following AWS tagging best practices)"
  type        = map(string)
  default = {
    Owner       = "terraform-aws-rds"
    Environment = "dev"
    Purpose     = "cross-region-manual-snapshot-copy"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to merge with default tags"
  type        = map(string)
  default     = {}
}