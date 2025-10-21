# ---------------------------------------------
# DB Instance Resource
# ---------------------------------------------

# Creates a random password (if not using AWS-managed password)
resource "random_string" "password" {
  count       = var.manage_master_user_password ? 0 : 1
  length      = 16
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  special     = false
}

# Creates a random id used in the final snapshot identifier (optional)
resource "random_id" "snapshot_identifier" {
  count = var.skip_final_snapshot ? 1 : 0
  keepers = {
    id = var.identifier
  }
  byte_length = 4
}

# Creates RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${local.account_alias}-${var.identifier}"

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = true
  kms_key_id        = var.kms_key_id
  license_model     = var.license_model

  # Database credentials
  db_name  = var.database_name
  username = var.is_replica ? null : var.username
  password = var.is_replica ? null : local.password

  port = var.port

  # Active Directory / IAM DB Auth
  domain                          = var.domain
  domain_iam_role_name            = var.domain_iam_role_name
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # Let AWS manage the master user password (non-replicas only)
  manage_master_user_password   = var.manage_master_user_password && (var.is_replica == false) ? true : null
  master_user_secret_kms_key_id = var.manage_master_user_password && (var.is_replica == false) ? var.master_user_secret_kms_key_id : null

  # Networking / groups
  vpc_security_group_ids = var.vpc_security_group_ids
  db_subnet_group_name   = local.db_subnet_group_name
  parameter_group_name   = local.db_parameter_group_name
  option_group_name      = local.db_option_group_name

  # Availability / performance
  availability_zone  = var.availability_zone
  multi_az           = var.multi_az
  iops               = var.iops
  publicly_accessible = var.publicly_accessible

  allow_major_version_upgrade = var.allow_major_version_upgrade
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  apply_immediately           = var.apply_immediately
  maintenance_window          = var.maintenance_window

  # Snapshots / backups
  snapshot_identifier       = var.snapshot_identifier
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier
  max_allocated_storage     = var.max_allocated_storage

  # Insights
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_id : null

  database_insights_mode = var.database_insights_mode

  # Replication / maintenance
  replicate_source_db = var.replicate_source_db
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window

  # Engine specific
  character_set_name = var.character_set_name
  ca_cert_identifier = var.ca_cert_identifier
  timezone           = var.timezone

  # Logging
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Deletion protection
  deletion_protection      = var.deletion_protection
  delete_automated_backups = var.delete_automated_backups

  # Optional point-in-time restore
  dynamic "restore_to_point_in_time" {
    for_each = var.restore_to_point_in_time == null ? [] : [var.restore_to_point_in_time]
    content {
      restore_time                          = lookup(restore_to_point_in_time.value, "restore_time", null)
      source_db_instance_identifier         = lookup(restore_to_point_in_time.value, "source_db_instance_identifier", null)
      #source_db_instance_automated_backups_arn = lookup(restore_to_point_in_time.value, "source_db_instance_automated_backups_arn", null)
      source_dbi_resource_id                = lookup(restore_to_point_in_time.value, "source_dbi_resource_id", null)
      use_latest_restorable_time            = lookup(restore_to_point_in_time.value, "use_latest_restorable_time", null)
    }
  }

  tags = merge(
    var.tags,
    { Name = "${local.account_alias}-${var.identifier}" }
  )

  timeouts {
    create = lookup(var.db_instance_timeouts, "create", null)
    delete = lookup(var.db_instance_timeouts, "delete", null)
    update = lookup(var.db_instance_timeouts, "update", null)
  }
}

# Enable Secrets Manager rotation for AWS-managed master user password
resource "aws_secretsmanager_secret_rotation" "main" {
  count     = var.manage_master_user_password && var.manage_master_user_password_rotation ? 1 : 0
  secret_id = aws_db_instance.main.master_user_secret[0].secret_arn

  rotation_rules {
    automatically_after_days = var.master_user_password_rotation_automatically_after_days
  }
}
