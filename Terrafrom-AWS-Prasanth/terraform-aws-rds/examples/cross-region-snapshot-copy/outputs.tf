################################################################################
# Outputs - Cross-Region Automated Backup Replication Example
################################################################################

# Primary RDS Instance Outputs
output "db_instance_id" {
  description = "Oracle SE2 RDS instance identifier"
  value       = module.oracle_primary.db_instance_identifier
}

output "db_instance_arn" {
  description = "Oracle SE2 RDS instance ARN"
  value       = module.oracle_primary.db_instance_arn
}

output "db_instance_endpoint" {
  description = "Oracle SE2 RDS instance endpoint"
  value       = module.oracle_primary.db_instance_endpoint
}

output "db_instance_port" {
  description = "Oracle SE2 RDS instance port"
  value       = module.oracle_primary.db_instance_port
}

# Cross-Region Backup Replication Outputs
output "backup_replication_arn" {
  description = "ARN of the automated backup replication"
  value       = aws_db_instance_automated_backups_replication.cross_region.id
}

output "backup_replication_source_arn" {
  description = "Source RDS instance ARN for backup replication"
  value       = aws_db_instance_automated_backups_replication.cross_region.source_db_instance_arn
}

# KMS Key Outputs
output "primary_kms_key_arn" {
  description = "Primary region KMS key ARN"
  value       = module.primary_kms.key_arn
}

output "secondary_kms_key_arn" {
  description = "Secondary region KMS key ARN"
  value       = module.secondary_kms.key_arn
}

# Security Group Output
output "security_group_id" {
  description = "Security group ID for Oracle SE2 RDS instance"
  value       = module.primary_security_group.security_group_id
}

# Implementation Summary
output "deployment_summary" {
  description = "Summary of the cross-region backup replication deployment"
  value = {
    database_engine    = "Oracle SE2"
    primary_region     = var.primary_region
    secondary_region   = var.secondary_region
    backup_method     = "AWS Automated Cross-Region Backup Replication"
    password_management = "AWS Secrets Manager"
    encryption        = "KMS encrypted (both regions)"
    
    features = [
      "Oracle SE2 with license-included",
      "Cross-region automated backup replication",
      "AWS Secrets Manager password rotation",
      "KMS encryption in both regions",
      "Least privilege security groups"
    ]
  }
}