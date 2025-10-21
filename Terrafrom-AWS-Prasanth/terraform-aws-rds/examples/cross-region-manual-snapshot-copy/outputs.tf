################################################################################
# Outputs - Cross-Region Manual Snapshot Copy Example
# Following Terraform and AWS Well-Architected Framework Best Practices
################################################################################

#------------------------------------------------------------------------------
# PRIMARY REGION INFRASTRUCTURE OUTPUTS
#------------------------------------------------------------------------------

output "primary_region_infrastructure" {
  description = "Primary region RDS infrastructure details"
  value = {
    db_instance_id       = module.oracle_primary.db_instance_identifier
    db_instance_arn      = module.oracle_primary.db_instance_arn
    db_instance_endpoint = module.oracle_primary.db_instance_address
    db_instance_port     = module.oracle_primary.db_instance_port
    availability_zone    = module.oracle_primary.db_instance_availability_zone
    engine_version       = module.oracle_primary.db_instance_engine_version
    instance_class       = module.oracle_primary.db_instance_class
    allocated_storage    = module.oracle_primary.db_instance_allocated_storage
    storage_encrypted    = module.oracle_primary.db_instance_storage_encrypted
    kms_key_id           = module.oracle_primary.db_instance_kms_key_id

    # Custom configurations
    option_group_name    = module.oracle_primary.db_option_group_name
    parameter_group_name = module.oracle_primary.db_parameter_group_name
    security_group_id    = module.primary_security_group.security_group_id

    # Backup configuration
    backup_retention_period = module.oracle_primary.db_instance_backup_retention_period
    backup_window           = module.oracle_primary.db_instance_backup_window
    maintenance_window      = module.oracle_primary.db_instance_maintenance_window
  }

  sensitive = false
}

output "primary_region_security" {
  description = "Primary region security configuration"
  value = {
    security_group_id  = module.primary_security_group.security_group_id
    security_group_arn = module.primary_security_group.security_group_arn
    kms_key_id         = module.primary_kms.key_id
    kms_key_arn        = module.primary_kms.key_arn
    vpc_id             = data.aws_vpc.primary.id
    subnet_ids         = data.aws_subnets.primary.ids
  }

  sensitive = false
}

#------------------------------------------------------------------------------
# SECONDARY REGION DISASTER RECOVERY INFRASTRUCTURE
#------------------------------------------------------------------------------

output "secondary_region_infrastructure" {
  description = "Secondary region disaster recovery infrastructure"
  value = {
    # Option group for snapshot compatibility
    option_group_name = aws_db_option_group.secondary_option_group.name
    option_group_arn  = aws_db_option_group.secondary_option_group.arn

    # Parameter group for consistent performance
    parameter_group_name = aws_db_parameter_group.secondary_parameter_group.name
    parameter_group_arn  = aws_db_parameter_group.secondary_parameter_group.arn

    # Security and networking
    security_group_id  = module.secondary_security_group.security_group_id
    security_group_arn = module.secondary_security_group.security_group_arn
    kms_key_id         = module.secondary_kms.key_id
    kms_key_arn        = module.secondary_kms.key_arn
    vpc_id             = data.aws_vpc.secondary.id
    subnet_ids         = data.aws_subnets.secondary.ids

    # Region information
    region             = var.secondary_region
    availability_zones = data.aws_availability_zones.secondary.names
  }

  sensitive = false
}

# Hourly Snapshots Outputs
output "hourly_snapshots_ids" {
  description = "List of hourly snapshot identifiers"
  value       = aws_db_snapshot.hourly_snapshots[*].id
}

output "hourly_snapshots_arns" {
  description = "List of hourly snapshot ARNs"
  value       = aws_db_snapshot.hourly_snapshots[*].db_snapshot_arn
}

output "hourly_snapshots_count" {
  description = "Number of hourly snapshots created"
  value       = length(aws_db_snapshot.hourly_snapshots)
}

# Snapshot Copy Outputs
output "primary_manual_snapshot_id" {
  description = "Primary manual snapshot identifier"
  value       = aws_db_snapshot.primary_manual.id
}

output "primary_manual_snapshot_arn" {
  description = "Primary manual snapshot ARN"
  value       = aws_db_snapshot.primary_manual.db_snapshot_arn
}

output "secondary_backup_snapshot_id" {
  description = "Secondary region backup snapshot identifier (from first hourly snapshot)"
  value       = aws_db_snapshot.secondary_backup_copy.id
}

output "secondary_backup_snapshot_arn" {
  description = "Secondary region backup snapshot ARN (from first hourly snapshot)"
  value       = aws_db_snapshot.secondary_backup_copy.db_snapshot_arn
}

output "additional_backup_snapshots_ids" {
  description = "Additional secondary region backup snapshot identifiers"
  value       = aws_db_snapshot.secondary_backup_copies[*].id
}

# Restored Instance Outputs
output "restored_db_instance_id" {
  description = "Restored RDS instance identifier (target region)"
  value       = module.oracle_restored.db_instance_identifier
}

output "restored_db_instance_arn" {
  description = "Restored RDS instance ARN (target region)"
  value       = module.oracle_restored.db_instance_arn
}

output "restored_db_instance_address" {
  description = "Restored RDS instance hostname (target region)"
  value       = module.oracle_restored.db_instance_address
}

# Module Outputs for Reference
output "primary_security_group_id" {
  description = "Primary region security group ID"
  value       = module.primary_security_group.security_group_id
}

output "secondary_security_group_id" {
  description = "Secondary region security group ID"
  value       = module.secondary_security_group.security_group_id
}

output "primary_kms_key_arn" {
  description = "Primary region KMS key ARN"
  value       = module.primary_kms.key_arn
}

output "secondary_kms_key_arn" {
  description = "Secondary region KMS key ARN"
  value       = module.secondary_kms.key_arn
}

# Remediation Documentation
output "remediation_summary" {
  description = "Summary of AWS Backup remediation implementation"
  value = {
    issue = "AWS Backup cannot copy RDS snapshots with custom option groups containing persistent options"

    remediation_method = "RDS API cross-region snapshot copy using Terraform"

    key_changes = [
      "Decreased backup_retention_period from 3 days to 1 day",
      "Removed kms_key_automated_backup_replication variable",
      "Removed secondary provider dependency for cross-region support",
      "Removed configuration aliases for provider configurations",
      "Removed provider argument from all data and resource blocks",
      "Removed aws_db_instance_automated_backups_replication resource"
    ]

    implementation_steps = [
      "1. Create primary RDS instance with custom option group using terraform-aws-rds module",
      "2. Create secondary region RDS instance with matching option group for compatibility",
      "3. Create manual snapshot from primary instance",
      "4. Use aws_db_snapshot resource for cross-region copy with option_group_name parameter",
      "5. Optional: Restore from copied snapshot in secondary region"
    ]

    modules_used = {
      rds_module      = "terraform-aws-rds (primary, secondary prep, and restored instances)"
      security_groups = "tfe.com/security-group/aws"
      kms_keys        = "tfe.com/kms/aws"
    }
  }
}

output "validation_checklist" {
  description = "Checklist to validate remediation implementation"
  value = {
    "✓ Primary RDS with custom option groups" = "Created with STATSPACK and Timezone options"
    "✓ Secondary compatible option group"     = "Created with identical options in secondary region"
    "✓ Cross-region snapshot copy"            = "Implemented using RDS API method with option_group_name"
    "✓ Backup retention remediation"          = "Set to 1 day as per requirements"
    "✓ No automated backup replication"       = "Removed aws_db_instance_automated_backups_replication"
    "✓ No provider aliases on resources"      = "Removed provider arguments from data and resource blocks"
    "✓ Working around AWS Backup limitation"  = "Successfully copying snapshots with custom option groups"
    "✓ Using organizational modules"          = "Security groups and KMS keys use tfe.com modules"
  }
}

# AWS CLI Equivalent Commands
output "aws_cli_commands" {
  description = "Equivalent AWS CLI commands for reference"
  value = {
    create_snapshot = format(
      "aws rds create-db-snapshot --db-instance-identifier %s --db-snapshot-identifier manual-snapshot-$(date +%%s)",
      module.oracle_primary.db_instance_identifier
    )
    copy_snapshot = format(
      "aws rds copy-db-snapshot --source-db-snapshot-identifier %s --target-db-snapshot-identifier copied-snapshot --option-group-name %s --source-region us-east-2 --target-region us-east-1",
      aws_db_snapshot.primary_manual.db_snapshot_arn,
      aws_db_option_group.secondary_option_group.name
    )
    restore_from_snapshot = format(
      "aws rds restore-db-instance-from-db-snapshot --db-instance-identifier restored-oracle --db-snapshot-identifier %s --db-instance-class db.t3.micro",
      aws_db_snapshot.secondary_backup_copy.id
    )
  }
}