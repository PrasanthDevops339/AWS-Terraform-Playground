############################################
# DB Instance - Variables
############################################

variable "identifier" {
  description = "(Required) The name of the RDS instance, if omitted, Terraform will assign a random, unique identifier"
  type        = string
  default     = null
}

variable "allocated_storage" {
  description = "(Required unless a snapshot_identifier or replicate_source_db is provided) The allocated storage in gigabytes"
  type        = string
  default     = null
}

variable "storage_type" {
  description = "(Optional) One of 'standard' (magnetic), 'gp2'/'gp3' (general purpose SSD), or 'io1' (provisioned IOPS SSD)."
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["standard", "gp2", "gp3", "io1"], var.storage_type)
    error_message = "Valid values are standard,gp2,gp3,io1"
  }
}

variable "performance_insights_enabled" {
  description = "(Optional) Specifies whether Performance Insights are enabled"
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "(Optional) The amount of time in days to retain Performance Insights data. Either 7 (7 days) or 731 (2 years)."
  type        = number
  default     = null
}

variable "database_insights_mode" {
  description = "(Optional) Mode for Database Insights that are enabled for the instance, must be 'standard' or 'advanced'"
  type        = string
  default     = null
  validation {
    condition     = var.database_insights_mode == null || contains(["standard", "advanced"], var.database_insights_mode)
    error_message = "Valid values are null, 'standard' and 'advanced'"
  }
}

variable "kms_key_id" {
  description = <<EOT
(Optional) The ARN for the KMS encryption key. If creating an encrypted replica, set this to the destination KMS ARN.
If storage_encrypted is set to true and kms_key_id is not specified the default KMS key created in your account will be used.
NOTE: if this key is changed to a new one and you have 'performance_insights_enabled' you must deploy the instance again.
EOT
  type        = string
  default     = null
}

variable "replicate_source_db" {
  description = "(Optional) Specifies that this resource is a Replicate database, and to use this value as the source database. This correlates to the identifier of another Amazon RDS Database to replicate."
  type        = string
  default     = null
}

variable "snapshot_identifier" {
  description = "(Optional) Specifies whether or not to create this database from a snapshot. This correlates to the snapshot ID you'd find in the RDS console, e.g: rds:production-2015-06-26-06-05."
  type        = string
  default     = null
}

variable "license_model" {
  description = "(Optional) License model information for this DB instance. Optional, but required for some DB engines, i.e. Oracle SE1"
  type        = string
  default     = null
}

variable "iam_database_authentication_enabled" {
  description = "(Optional) Specifies whether or mappings of AWS Identity and Access Management (IAM) accounts to database accounts is enabled"
  type        = bool
  default     = false
}

variable "domain" {
  description = "(Optional) The ID of the Directory Service Active Directory domain to create the instance in"
  type        = string
  default     = null
}

variable "domain_iam_role_name" {
  description = "(Required if domain is provided) The name of the IAM role to be used when making API calls to the Directory Service"
  type        = string
  default     = null
}

variable "engine" {
  description = "(Optional) The database engine to use"
  type        = string
  default     = null
}

variable "engine_version" {
  description = "(Optional) The engine version to use"
  type        = string
  default     = null
}

variable "instance_class" {
  description = "(Optional) The instance type of the RDS instance"
  type        = string
  default     = "db.t3.large"
}

variable "database_name" {
  description = "(Required) The DB name to create. If omitted, no database is created initially"
  type        = string
  default     = null
}

variable "username" {
  description = "(Required) Username for the master DB user"
  type        = string
  default     = null
}

variable "manage_master_user_password" {
  description = "(Optional) Set to true to allow RDS to manage the master user password in Secrets Manager. Cannot be set if password is provided"
  type        = bool
  default     = true
}

variable "manage_master_user_password_rotation" {
  description = "(Optional) Whether to manage the master user password rotation. Setting this value to false after previously having been set to true will disable automatic rotation."
  type        = bool
  default     = true
}

variable "master_user_password_rotation_automatically_after_days" {
  description = "Specifies the number of days between automatic scheduled rotations of the secret."
  type        = number
  default     = 30
}

variable "master_user_secret_kms_key_id" {
  description = "(Optional) The key ARN, key ID, alias ARN or alias name for the KMS key to encrypt the master user password secret in Secrets Manager."
  type        = string
  default     = null
}

variable "port" {
  description = "(Optional) The port on which the DB accepts connections"
  type        = string
  default     = null
}

variable "final_snapshot_identifier" {
  description = "(Optional) The name of your final DB snapshot when this DB instance is deleted."
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "(Optional) List of VPC security groups to associate"
  type        = list(string)
  default     = []
}

variable "db_subnet_group_name" {
  description = "(Optional) Name of DB subnet group. DB instance will be created in the VPC associated with the DB subnet group. If unspecified, will be created in the default VPC"
  type        = string
  default     = null
}

variable "create_subnet_group" {
  description = "Whether to create subnet group resource or not?"
  type        = bool
  default     = true
}

variable "db_parameter_group_name" {
  description = "(Optional) Name of the DB parameter group to associate"
  type        = string
  default     = null
}

variable "availability_zone" {
  description = "(Optional) The Availability Zone of the RDS instance"
  type        = string
  default     = null
}

variable "multi_az" {
  description = "(Optional) Specifies if the RDS instance is multi-AZ"
  type        = bool
  default     = true
}

variable "iops" {
  description = "(Optional) The amount of provisioned IOPS. Setting this implies a storage_type of 'io1'"
  type        = number
  default     = null
}

variable "publicly_accessible" {
  description = "(Optional) Bool to control if instance is publicly accessible"
  type        = bool
  default     = false
}

variable "allow_major_version_upgrade" {
  description = "(Optional) Indicates that major version upgrades are allowed. Changing this parameter does not result in an outage and the change is asynchronously applied as soon as possible"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "(Optional) Indicates that minor engine upgrades will be applied automatically to the DB instance during the maintenance window"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "(Optional) Specifies whether any database modifications are applied immediately, or during the next maintenance window"
  type        = bool
  default     = false
}

variable "maintenance_window" {
  description = "(Optional) The window to perform maintenance in. Syntax: 'ddd:hh24:mi-ddd:hh24:mi'. Eg: 'Mon:00:00-Mon:03:00'"
  type        = string
  default     = "Mon:00:00-Mon:03:00"
}

variable "skip_final_snapshot" {
  description = "(Optional) Determines whether a final DB snapshot is created before the DB instance is deleted. If true is specified, no DB snapshot is created. If false is specified, a DB snapshot is created before the DB instance is deleted, using the value from final_snapshot_identifier"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "(Optional) The days to retain backups for"
  type        = number
  default     = null
}

variable "backup_window" {
  description = "(Optional) The daily time range (in UTC) during which automated backups are created if they are enabled. Example: '03:00-06:00'. Must not overlap with maintenance_window"
  type        = string
  default     = "03:00-06:00"
}

variable "timezone" {
  description = "(Optional) Time zone of the DB instance. timezone is currently only supported by Microsoft SQL Server. The timezone can only be set on creation. See MSSQL User Guide for more information."
  type        = string
  default     = null
}

variable "character_set_name" {
  description = "(Optional) The character set name to use for DB encoding in Oracle instances. This can’t be changed. See Oracle Character Sets Supported in Amazon RDS for more information"
  type        = string
  default     = null
}

variable "enabled_cloudwatch_logs_exports" {
  description = "(Optional) A list of log types to enable for exporting to Cloudwatch logs. If omitted, no logs will be exported. Valid values (depending on engine): alert, audit, error, general, listener, slowquery, trace, postgresql (PostgreSQL), upgrade (PostgreSQL)."
  type        = list(string)
  default     = []
}

variable "db_instance_timeouts" {
  description = "(Optional) Updated Terraform resource management timeouts. Applies to `aws_db_instance` in particular to permit resource management times"
  type        = map(string)
  default = {
    create = "40m"
    delete = "40m"
    update = "40m"
  }
}

variable "deletion_protection" {
  description = "(Optional) The database can't be deleted when this value is set to true."
  type        = bool
  default     = false
}

variable "max_allocated_storage" {
  description = "(Optional) Specifies the value for Storage Autoscaling"
  type        = number
  default     = null
}

variable "ca_cert_identifier" {
  description = "(Optional) Specifies the identifier of the CA certificate for the DB instance"
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

variable "delete_automated_backups" {
  description = "(Optional) Specifies whether to remove automated backups immediately after the DB instance is deleted"
  type        = bool
  default     = true
}

variable "iam_partition" {
  description = "(Optional) IAM Partition to use when generating ARNs*. For most regions this can be left at default. China/Govcloud use different partitions"
  type        = string
  default     = null
}

variable "restore_to_point_in_time" {
  description = "(Optional) A configuration block for restoring a DB instance to an arbitrary point in time."
  type        = map(string)
  default     = null
}

############################################
# DB Instance - Option Group Variables
############################################

variable "db_option_group_name" {
  description = "(Optional) Name of the DB option group to associate."
  type        = string
  default     = null
}

variable "option_group_description" {
  description = "(Optional) The description of the option group"
  type        = string
  default     = null
}

variable "major_engine_version" {
  description = "(Optional) Specifies the major version of the engine that this option group should be associated with"
  type        = string
  default     = null
}

variable "options" {
  description = "(Optional) A list of Options to apply"
  type        = any
  default     = []
}

variable "option_group_timeouts" {
  description = "(Optional) Define maximum timeout for deletion of `aws_db_option_group` resource"
  type        = map(string)
  default = {
    delete = "15m"
  }
}

############################################
# DB Instance - Parameter Group Variables
############################################

variable "parameter_group_description" {
  description = "(Optional) The description of the DB parameter group"
  type        = string
  default     = null
}

variable "family" {
  description = "(Optional) The family of the DB parameter group"
  type        = string
  default     = null
}

variable "parameters" {
  description = "(Optional) A list of DB parameter maps to apply. Note that parameters may differ from a family to an other"
  type        = list(map(string))
  default     = []
}

############################################
# DB Instance - Subnet Group Variables
############################################

variable "subnet_ids" {
  description = "(Required) A list of VPC subnet IDs"
  type        = list(string)
  default     = []
}

############################################
# DB Instance - CloudWatch / Events Variables
############################################

variable "logs_retention_period" {
  description = "(Optional) Number of days to retain logs in Cloudwatch"
  type        = number
  default     = 7
}

variable "enable_db_event_subscription" {
  description = "(Optional) Boolean to enable the subscription on list of db events to send alert"
  type        = bool
  default     = true
}

variable "db_events_list" {
  description = "(Optional) List of db events to receive alerts on subscription"
  type        = list(any)
  default     = ["availability", "deletion", "failover", "failure", "low storage"]
}

variable "sns_topic_arn" {
  description = "(Optional) ARN of the sns topic to receive the alerts on the db instance events."
  type        = string
  default     = null
}

############################################
# Secrets Manager
############################################

variable "recovery_window_in_days" {
  description = "(Optional) Number of days that AWS Secrets Manager waits before it can delete the secret. This value can be 0 to force deletion without recovery or range from 7 to 30 days"
  type        = number
  default     = 0
}

############################################
# Tagging / Misc
############################################

variable "tags" {
  description = "(Required) Default tag values to be applied to all resources."
  type        = map(string)
  default     = {}
}

variable "is_replica" {
  description = "To be set to true when using module to create read-replica"
  type        = bool
  default     = false
}
