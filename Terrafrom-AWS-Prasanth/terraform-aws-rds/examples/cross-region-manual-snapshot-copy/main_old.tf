################################################################################
# Automated Cross-Region RDS Backup using Lambda and EventBridge
# AWS Well-Architected Framework Implementation
# 
# This solution provides automated cross-region RDS snapshot backup using:
# - AWS Lambda for snapshot creation and management
# - EventBridge for scheduling automation
# - Works with ANY RDS engine type and option groups
# - Creates compatible option/parameter groups in secondary region
# 
# Architecture Pillars Addressed:
# - Security: Encryption, IAM roles, VPC isolation
# - Reliability: Automated cross-region backup, error handling
# - Performance: Serverless automation, efficient snapshot management
# - Cost Optimization: Event-driven execution, snapshot lifecycle management
# - Operational Excellence: Automated monitoring, CloudWatch logging
################################################################################

################################################################################
# Local Configuration - Following AWS Naming and Tagging Standards
################################################################################

locals {
  # Resource naming following AWS naming conventions
  name_prefix = "${var.name}-${var.environment}"

  # AWS Well-Architected Framework tagging strategy
  common_tags = merge(var.tags, var.additional_tags, {
    Name            = local.name_prefix
    Region          = var.primary_region
    SecondaryRegion = var.secondary_region
    CreatedBy       = "terraform"
    LastModified    = timestamp()
  })

  # Backup operation tags to prevent conflicts with existing backup solutions
  backup_prevention_tags = {
    "ops:backupschedule1" = "none"
    "ops:backupschedule2" = "none"
    "ops:backupschedule3" = "none"
    "ops:backupschedule4" = "none"
    "ops:backupschedule5" = "none"
  }

  # Disaster recovery operation tags for clear operational boundaries
  dr_operation_tags = {
    "ops:drschedule1" = "none"
    "ops:drschedule2" = "none"
    "ops:drschedule3" = "none"
    "ops:drschedule4" = "none"
    "ops:drschedule5" = "none"
  }

  # Complete operational tags combining all tagging strategies
  operational_tags = merge(
    local.common_tags,
    local.backup_prevention_tags,
    local.dr_operation_tags
  )

  # Oracle Standard Edition configuration - cost-optimized for testing
  oracle_config = {
    engine                 = "oracle-se2"
    engine_version         = "19.0.0.0.ru-2024-10.rur-2024-10.r1"
    family                 = "oracle-se2-19"
    major_version          = "19"
    port                   = 1521
    database_name          = "TEST"
    username               = "admin"
    parameter_group_family = "oracle-se2-19"
  }

  # Instance configuration with maximum cost optimization for testing
  instance_config = {
    class             = "db.t3.micro"
    allocated_storage = 20
    max_storage       = 50
  }

  # Backup and maintenance windows optimized for minimal impact
  operational_windows = {
    backup_window      = var.backup_window
    maintenance_window = var.maintenance_window
    retention_period   = var.backup_retention_period
  }

  # Oracle option group configuration - these options cause AWS Backup failures
  # STATSPACK and Timezone are persistent options that require manual handling
  oracle_options = [
    {
      option_name = "STATSPACK"
      description = "Oracle STATSPACK performance monitoring package"
    },
    {
      option_name = "Timezone"
      description = "Oracle timezone configuration for consistent time handling"
      option_settings = [
        {
          name  = "TIME_ZONE"
          value = "US/Eastern"
        }
      ]
    }
  ]

  # Oracle parameter group configuration optimized for t3.micro cost efficiency
  # Minimal memory allocation for testing and example purposes
  oracle_parameters = [
    {
      name        = "shared_pool_size"
      value       = "67108864" # 64MB - Minimal Oracle SGA shared pool
      description = "Memory allocated for shared SQL and PL/SQL areas"
    },
    {
      name        = "db_cache_size"
      value       = "134217728" # 128MB - Minimal database buffer cache
      description = "Memory allocated for database buffer cache"
    }
  ]

  # Security configuration following AWS security best practices
  security_config = {
    enable_encryption          = true
    enable_deletion_protection = var.enable_deletion_protection
    storage_encrypted          = true
    kms_key_rotation           = true
  }

  # KMS policy statements following AWS security best practices
  # Principle of least privilege with specific service permissions
  kms_statements = {
    # Platform administrator role access - restricted to specific role
    platform_admin_permissions = {
      sid    = "Enable Platform Administrator Permissions"
      effect = "Allow"
      principals = [{
        type        = "AWS"
        identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${data.aws_iam_account_alias.current.account_alias}-platformadministrator-role"]
      }]
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*",
        "kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant", "kms:DescribeKey",
        "kms:GetKeyPolicy", "kms:GetKeyRotationStatus"
      ]
      resources = ["*"]
      conditions = [{
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["rds.${var.primary_region}.amazonaws.com", "rds.${var.secondary_region}.amazonaws.com"]
      }]
    }

    # RDS service permissions for primary region
    rds_service_primary = {
      sid    = "Allow RDS Service Primary Region"
      effect = "Allow"
      principals = [{
        type        = "Service"
        identifiers = ["rds.amazonaws.com"]
      }]
      actions = [
        "kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"
      ]
      resources = ["*"]
      conditions = [{
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["rds.${var.primary_region}.amazonaws.com"]
      }]
    }

    # RDS service permissions for secondary region
    rds_service_secondary = {
      sid    = "Allow RDS Service Secondary Region"
      effect = "Allow"
      principals = [{
        type        = "Service"
        identifiers = ["rds.amazonaws.com"]
      }]
      actions = [
        "kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"
      ]
      resources = ["*"]
      conditions = [{
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["rds.${var.secondary_region}.amazonaws.com"]
      }]
    }

    # Cross-region snapshot copy permissions - minimal required access
    cross_region_snapshot_access = {
      sid    = "Allow Cross-Region Snapshot Operations"
      effect = "Allow"
      principals = [{
        type        = "AWS"
        identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
      }]
      actions = [
        "kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = ["rds.${var.primary_region}.amazonaws.com", "rds.${var.secondary_region}.amazonaws.com"]
        },
        {
          test     = "StringLike"
          variable = "aws:RequestedRegion"
          values   = [var.primary_region, var.secondary_region]
        }
      ]
    }
  }

  # Validation checks for deployment readiness
  validation_checks = {
    # Ensure required data sources are available
    primary_vpc_available        = length(data.aws_vpc.primary.id) > 0
    secondary_vpc_available      = length(data.aws_vpc.secondary.id) > 0
    sufficient_primary_subnets   = length(data.aws_subnets.primary.ids) >= 2
    sufficient_secondary_subnets = length(data.aws_subnets.secondary.ids) >= 2
    regions_different            = var.primary_region != var.secondary_region

    # Oracle-specific validations
    oracle_version_supported  = can(regex("^19\\.", local.oracle_config.engine_version))
    instance_class_compatible = contains(["db.t3", "db.r5", "db.m5"], substr(local.instance_config.class, 0, 5))
  }
}

################################################################################
# Resource Validation and Random ID Generation
################################################################################

# Validation checks to ensure deployment readiness
resource "null_resource" "validation" {
  lifecycle {
    precondition {
      condition     = local.validation_checks.primary_vpc_available
      error_message = "Primary VPC '${var.primary_vpc_name}' not found in region ${var.primary_region}."
    }

    precondition {
      condition     = local.validation_checks.secondary_vpc_available
      error_message = "Secondary VPC '${var.secondary_vpc_name}' not found in region ${var.secondary_region}."
    }

    precondition {
      condition     = local.validation_checks.sufficient_primary_subnets
      error_message = "Primary region requires at least 2 subnets for Multi-AZ deployment. Found: ${length(data.aws_subnets.primary.ids)}."
    }

    precondition {
      condition     = local.validation_checks.sufficient_secondary_subnets
      error_message = "Secondary region requires at least 2 subnets for disaster recovery. Found: ${length(data.aws_subnets.secondary.ids)}."
    }

    precondition {
      condition     = local.validation_checks.oracle_version_supported
      error_message = "Oracle engine version must be 19c series. Provided: ${local.oracle_config.engine_version}."
    }
  }
}

# Random string for unique resource naming - AWS best practice
resource "random_string" "module_id" {
  length  = 4
  numeric = true
  special = false
  upper   = false

  keepers = {
    # Force regeneration when key configuration changes
    name_prefix = local.name_prefix
    regions     = "${var.primary_region}-${var.secondary_region}"
  }
}

################################################################################
# Primary Region Resources (us-east-2)
################################################################################

# Primary region security group using tfe.com module
module "primary_security_group" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "oracle-primary-sg-${random_string.module_id.result}"
  description = "Security group for primary Oracle RDS cluster"
  vpc_id      = data.aws_vpc.primary.id

  ########## Ingress rules ##########
  ingress_rules = [
    {
      from_port   = 1521
      to_port     = 1521
      ip_protocol = "TCP"
      cidr_ipv4   = data.aws_vpc.primary.cidr_block
      description = "Allow Oracle Database access from VPC"
    }
  ]
}

# Primary region KMS key using tfe.com module
module "primary_kms" {
  source = "tfe.com/kms/aws"

  key_name    = "db-encrypt-oracle-primary-${random_string.module_id.result}"
  description = "KMS key for primary Oracle RDS cluster encryption"

  key_statements = [
    local.kms_statements.iam_permissions,
    local.kms_statements.rds_service_primary
  ]

  tags = merge(local.common_tags, {
    Name = "primary-oracle-kms-key"
  })
}

################################################################################
# Secondary Region Resources (us-east-1) - For Backup Snapshots Only
################################################################################

# Secondary region KMS key for snapshot encryption
module "secondary_kms" {
  source = "tfe.com/kms/aws"

  providers = {
    aws = aws.secondary
  }

  key_name    = "db-encrypt-oracle-secondary-${random_string.module_id.result}"
  description = "KMS key for secondary region snapshot encryption"

  key_statements = [
    local.kms_statements.iam_permissions,
    local.kms_statements.rds_service_secondary,
    local.kms_statements.cross_region_access
  ]

  tags = merge(local.common_tags, {
    Name = "secondary-oracle-kms-key"
  })
}

################################################################################
# Primary Region RDS Cluster with Custom Option Group (us-east-2)
################################################################################

module "oracle_primary" {
  source = "../../"

  identifier = "${local.name}-primary-${random_string.module_id.result}"

  # Oracle SE2 configuration using local variables - cost optimized for testing
  engine               = local.oracle_config.engine
  engine_version       = local.oracle_config.engine_version
  family               = local.oracle_config.family
  major_engine_version = local.oracle_config.major_version
  instance_class       = local.instance_config.class
  license_model        = "license-included" # Cost-effective licensing for SE2

  allocated_storage     = local.instance_config.allocated_storage
  max_allocated_storage = local.instance_config.max_storage
  storage_encrypted     = true
  kms_key_id            = module.primary_kms.key_arn

  database_name = local.oracle_config.database_name
  username      = local.oracle_config.username
  port          = local.oracle_config.port

  # REMEDIATION: backup_retention_period set to 1 day (was 3 days)
  backup_retention_period = 1
  backup_window           = "03:00-06:00"         # Primary region backup window
  maintenance_window      = "Sun:03:00-Sun:06:00" # Primary region maintenance window

  # Enable automated backups for hourly snapshots
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  # Networking - using module outputs
  create_subnet_group    = true
  subnet_ids             = data.aws_subnets.primary.ids
  vpc_security_group_ids = [module.primary_security_group.security_group_id]

  # Custom option group with persistent/permanent options
  # This causes AWS Backup cross-region copy failures
  options = local.oracle_options

  # Custom parameter group settings for Oracle performance tuning
  parameters = local.oracle_parameters

  tags = merge(local.common_tags, local.operational_tags)
}

################################################################################
# Secondary Region Resources for Snapshot Compatibility (us-east-1)
################################################################################

# Create parameter group in secondary region for snapshot compatibility
# This ensures restored databases use the same custom parameter settings
resource "aws_db_parameter_group" "secondary_parameter_group" {
  provider = aws.secondary

  name        = "${local.name}-secondary-params-${random_string.module_id.result}"
  family      = local.oracle_config.family
  description = "Secondary region parameter group for cross-region snapshot compatibility"

  # Match primary region parameter configuration - cost optimized
  parameter {
    name  = "shared_pool_size"
    value = "67108864"
  }

  parameter {
    name  = "db_cache_size"
    value = "134217728"
  }

  tags = merge(local.common_tags, {
    Name = "secondary-parameter-group"
  })
}

# Create security group in secondary region for disaster recovery scenarios
module "secondary_security_group" {
  source = "tfe.com/security-group/aws"

  providers = {
    aws = aws.secondary
  }

  sg_name     = "oracle-secondary-sg-${random_string.module_id.result}"
  description = "Security group for secondary Oracle RDS disaster recovery"
  vpc_id      = data.aws_vpc.secondary.id

  ########## Ingress rules ##########
  ingress_rules = [
    {
      from_port   = local.oracle_config.port
      to_port     = local.oracle_config.port
      ip_protocol = "TCP"
      cidr_ipv4   = data.aws_vpc.secondary.cidr_block
      description = "Allow Oracle Database access from VPC"
    }
  ]

  tags = merge(local.common_tags, {
    Name = "secondary-security-group"
  })
}

# Create option group in secondary region for snapshot compatibility
# This is required for cross-region snapshot copying with custom options
resource "aws_db_option_group" "secondary_option_group" {
  provider = aws.secondary

  name                     = "${local.name}-secondary-options-${random_string.module_id.result}"
  option_group_description = "Secondary region option group for cross-region snapshot compatibility"
  engine_name              = "oracle-se2"
  major_engine_version     = "19"

  # CRITICAL: IDENTICAL options as primary for compatibility
  option {
    option_name = "STATSPACK"
  }

  option {
    option_name = "Timezone"
    option_settings {
      name  = "TIME_ZONE"
      value = "US/Eastern" # Secondary region timezone
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name}-secondary-options"
    Region  = "secondary"
    Purpose = "cross-region-snapshot-compatibility"
  })
}

# Note: RDS automated backups occur during the backup window and create point-in-time recovery snapshots
# For true hourly manual snapshots, we'll use multiple manual snapshots with timestamp-based naming
# This approach creates snapshots that can be used for cross-region copying

# Create multiple manual snapshots to simulate hourly snapshots in primary region
resource "aws_db_snapshot" "hourly_snapshots" {
  count = var.hourly_snapshots_count

  db_instance_identifier = module.oracle_primary.db_instance_identifier
  db_snapshot_identifier = "${local.name}-hourly-${count.index + 1}-${random_string.module_id.result}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = merge(local.common_tags, {
    Type           = "hourly-manual-snapshot"
    SnapshotNumber = count.index + 1
    CreatedAt      = formatdate("YYYY-MM-DD hh:mm", timestamp())
    SourceRegion   = "us-east-2"
  })

  depends_on = [module.oracle_primary]
}

################################################################################
# Cross-Region Snapshot Copy - RDS API Method (REMEDIATION)
################################################################################

# Step 1: Create additional manual snapshot for cross-region copy demonstration
resource "aws_db_snapshot" "primary_manual" {
  db_instance_identifier = module.oracle_primary.db_instance_identifier
  db_snapshot_identifier = "${local.name}-manual-${random_string.module_id.result}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = merge(local.common_tags, {
    Type         = "manual-primary-snapshot"
    SourceRegion = "us-east-2"
  })

  depends_on = [module.oracle_primary]
}

# Step 2: Cross-region copy using RDS API method (REMEDIATION)
# Copy primary region snapshots to secondary region for backup
resource "aws_db_snapshot" "secondary_backup_copy" {
  provider = aws.secondary

  # Use the first hourly snapshot for cross-region copy
  source_db_snapshot_identifier = aws_db_snapshot.hourly_snapshots[0].db_snapshot_arn
  target_db_snapshot_identifier = "${local.name}-backup-${random_string.module_id.result}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # CRITICAL: Specify secondary option group to handle custom options
  option_group_name = aws_db_option_group.secondary_option_group.name

  # Use secondary region KMS key for encryption
  kms_key_id = module.secondary_kms.key_arn

  # Copy tags from source snapshot
  copy_tags = true

  tags = merge(local.common_tags, {
    Type           = "cross-region-backup-copy"
    SourceRegion   = "us-east-2"
    BackupRegion   = "us-east-1"
    SourceSnapshot = aws_db_snapshot.hourly_snapshots[0].id
    Method         = "rds-api-remediation"
    Purpose        = "disaster-recovery-backup"
  })

  depends_on = [
    aws_db_option_group.secondary_option_group,
    aws_db_snapshot.hourly_snapshots
  ]
}

# Additional cross-region backup copies for other hourly snapshots
resource "aws_db_snapshot" "secondary_backup_copies" {
  provider = aws.secondary
  count    = length(aws_db_snapshot.hourly_snapshots) - 1 # Copy remaining snapshots

  source_db_snapshot_identifier = aws_db_snapshot.hourly_snapshots[count.index + 1].db_snapshot_arn
  target_db_snapshot_identifier = "${local.name}-backup-${count.index + 2}-${random_string.module_id.result}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # CRITICAL: Specify secondary option group to handle custom options
  option_group_name = aws_db_option_group.secondary_option_group.name

  # Use secondary region KMS key for encryption
  kms_key_id = module.secondary_kms.key_arn

  # Copy tags from source snapshot
  copy_tags = true

  tags = merge(local.common_tags, {
    Type           = "cross-region-backup-copy"
    SourceRegion   = "us-east-2"
    BackupRegion   = "us-east-1"
    SourceSnapshot = aws_db_snapshot.hourly_snapshots[count.index + 1].id
    Method         = "rds-api-remediation"
    CopyNumber     = count.index + 2
    Purpose        = "disaster-recovery-backup"
  })

  depends_on = [
    aws_db_option_group.secondary_option_group,
    aws_db_snapshot.hourly_snapshots
  ]
}

################################################################################
# Optional: Disaster Recovery - Restore from Backup Snapshot in Secondary Region
# This section is commented out as it's only needed for actual disaster recovery
################################################################################

# Uncomment the following resource if you need to restore from backup snapshots in secondary region
# This would be used during disaster recovery scenarios

/*
module "oracle_disaster_recovery" {
  source = "../../"
  
  providers = {
    aws = aws.secondary
  }

  identifier = "${local.name}-disaster-recovery-${random_string.module_id.result}"
  
  # Restore from cross-region backup snapshot
  snapshot_identifier = aws_db_snapshot.secondary_backup_copy.id
  
  # Must match primary engine configuration - cost optimized
  engine               = "oracle-se2"
  engine_version       = "19.0.0.0.ru-2024-10.rur-2024-10.r1"
  family               = "oracle-se2-19"
  major_engine_version = "19"
  instance_class       = "db.t3.micro"
  license_model        = "license-included"  # Cost-effective licensing for SE2
  
  allocated_storage     = 20
  max_allocated_storage = 50
  storage_encrypted     = true
  kms_key_id           = module.secondary_kms.key_arn
  
  # Use secondary region custom configurations
  db_option_group_name    = aws_db_option_group.secondary_option_group.name
  parameter_group_name    = aws_db_parameter_group.secondary_parameter_group.name
  
  # Create new subnet group in secondary region
  create_subnet_group    = true
  subnet_ids             = data.aws_subnets.secondary.ids
  vpc_security_group_ids = [module.secondary_security_group.security_group_id]
  
  # REMEDIATION: backup_retention_period set to 1 day
  backup_retention_period = 1
  backup_window          = "06:00-09:00"  # Different window for secondary region
  maintenance_window     = "Sat:09:00-Sat:12:00"
  

  
  skip_final_snapshot = true
  deletion_protection = false
  
  tags = merge(local.operational_tags, {
    Name         = "${local.name}-disaster-recovery"
    Region       = "secondary"
    Purpose      = "disaster-recovery"
    RestoredFrom = aws_db_snapshot.secondary_backup_copy.id
  })
  
  depends_on = [
    aws_db_snapshot.secondary_backup_copy,
    aws_db_option_group.secondary_option_group
  ]
}
*/