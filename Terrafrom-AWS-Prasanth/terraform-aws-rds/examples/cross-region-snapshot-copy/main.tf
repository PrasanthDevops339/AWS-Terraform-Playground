# Terraform configuration for cross-region RDS backup using automated backup replication
# Simple, AWS-managed solution for cross-region disaster recovery

################################################################################
# Random ID and Local Values
################################################################################

resource "random_string" "module_id" {
  length  = 4
  special = false
  upper   = false
  numeric = true
  
  keepers = {
    # Force recreation if environment changes
    environment = var.environment
  }
}

locals {
  name_prefix = "${var.name}-${random_string.module_id.result}"
  
  # Standard tagging strategy
  common_tags = merge(var.tags, {
    Name        = local.name_prefix
    Environment = var.environment
    Module      = "terraform-aws-rds"
    Example     = "cross-region-automated-backup"
    ManagedBy   = "terraform"
    Repository  = "terraform-aws-rds"
  })
  
  # Resource naming convention
  resource_names = {
    primary_kms_key   = "rds-kms-primary-${local.name_prefix}"
    secondary_kms_key = "rds-kms-secondary-${local.name_prefix}"
    security_group    = "rds-sg-primary-${local.name_prefix}"
    db_instance       = "oracle-se2-primary-${local.name_prefix}"
    backup_replication = "backup-replication-${local.name_prefix}"
  }
}

################################################################################
# KMS Keys
################################################################################

# Primary region KMS key for RDS encryption
module "primary_kms" {
  source = "tfe.com/kms/aws"
  
  providers = {
    aws = aws.primary
  }
  
  key_name    = local.resource_names.primary_kms_key
  description = "KMS key for Oracle SE2 RDS encryption in ${var.primary_region}"
  
  key_statements = [
    {
      sid    = "EnableIAMUserPermissions"
      effect = "Allow"
      principals = [
        {
          type = "AWS"
          identifiers = [
            "arn:aws:iam::${var.account_id}:role/${data.aws_iam_account_alias.current.account_alias}-platform-administrator-role"
          ]
        }
      ]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
        "kms:ReEncrypt*",
        "kms:RetireGrant",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy"
      ]
      resources = ["*"]
    },
    {
      sid    = "AllowRDSService"
      effect = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["rds.amazonaws.com"]
        }
      ]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
        "kms:RetireGrant"
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = ["rds.${var.primary_region}.amazonaws.com"]
        }
      ]
    },
    {
      sid    = "AllowBackupService"
      effect = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["backup.amazonaws.com"]
        }
      ]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey"
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = ["backup.${var.primary_region}.amazonaws.com"]
        }
      ]
    }
  ]
  
  tags = local.common_tags
}

# Secondary region KMS key for backup replication
module "secondary_kms" {
  source = "tfe.com/kms/aws"
  
  providers = {
    aws = aws.secondary
  }
  
  key_name    = local.resource_names.secondary_kms_key
  description = "KMS key for Oracle SE2 RDS backup replication in ${var.secondary_region}"
  
  key_statements = [
    {
      sid    = "EnableIAMUserPermissions"
      effect = "Allow"
      principals = [
        {
          type = "AWS"
          identifiers = [
            "arn:aws:iam::${var.account_id}:role/${data.aws_iam_account_alias.current.account_alias}-platform-administrator-role"
          ]
        }
      ]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
        "kms:ReEncrypt*",
        "kms:RetireGrant",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy"
      ]
      resources = ["*"]
    },
    {
      sid    = "AllowRDSService"
      effect = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["rds.amazonaws.com"]
        }
      ]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
        "kms:RetireGrant"
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = ["rds.${var.secondary_region}.amazonaws.com"]
        }
      ]
    },
    {
      sid    = "AllowCrossRegionBackup"
      effect = "Allow"
      principals = [
        {
          type = "AWS"
          identifiers = [
            "arn:aws:iam::${var.account_id}:role/${data.aws_iam_account_alias.current.account_alias}-platform-administrator-role"
          ]
        }
      ]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
        "kms:ReEncrypt*",
        "kms:RetireGrant"
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = [
            "rds.${var.primary_region}.amazonaws.com",
            "rds.${var.secondary_region}.amazonaws.com"
          ]
        }
      ]
    },
    {
      sid    = "AllowBackupService"
      effect = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["backup.amazonaws.com"]
        }
      ]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
        "kms:ReEncrypt*"
      ]
      resources = ["*"]
      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = [
            "backup.${var.primary_region}.amazonaws.com",
            "backup.${var.secondary_region}.amazonaws.com"
          ]
        }
      ]
    }
  ]
  
  tags = local.common_tags
}

################################################################################
# Security Group
################################################################################

# Security group for RDS instance with least privilege access
module "primary_security_group" {
  source = "tfe.com/security-group/aws"
  
  providers = {
    aws = aws.primary
  }
  
  name        = local.resource_names.security_group
  description = "Security group for Oracle SE2 RDS instance - ${var.environment}"
  vpc_id      = data.aws_vpc.primary.id
  
  # Ingress rules - restrictive by default
  ingress_rules = [
    {
      from_port   = 1521
      to_port     = 1521
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
      description = "Oracle database access from authorized networks"
    }
  ]
  
  tags = local.common_tags
}



################################################################################
# RDS Instance
################################################################################

# Primary Oracle SE2 RDS instance with automated backup replication
module "oracle_primary" {
  source = "../../"
  
  providers = {
    aws = aws.primary
  }
  
  subnet_ids = data.aws_subnets.primary.ids
  identifier = "oracle-db-${random_string.module_id.result}"

  engine               = "oracle-se2"
  engine_version       = "19.0.0.0.ru-2024-10.rur-2024-10.r1"
  family               = "oracle-se2-19"
  major_engine_version = "19"
  instance_class       = "db.t3.large"
  license_model        = "license-included"

  # storage
  allocated_storage     = 80
  max_allocated_storage = 150

  # database config
  database_name                        = "TEST"
  username                             = "admin"
  port                                 = "1521"
  manage_master_user_password          = true
  manage_master_user_password_rotation = true
  kms_key_id                          = module.primary_kms.key_arn

  # database maintenance - Critical for cross-region replication
  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_retention_period = 7
  backup_window           = "03:00-06:00"

  # logging
  enabled_cloudwatch_logs_exports = ["alert"]

  character_set_name = "AL32UTF8"

  deletion_protection = false

  vpc_security_group_ids = [module.primary_security_group.security_group_id]

  tags = local.common_tags
}

################################################################################
# Cross-Region Automated Backups Replication
################################################################################

# Automated backup replication to secondary region
# Note: Compatible with Multi-AZ DB instances but NOT with Multi-AZ DB clusters
resource "aws_db_instance_automated_backups_replication" "cross_region" {
  provider = aws.secondary
  
  source_db_instance_arn = module.oracle_primary.db_instance_arn
  kms_key_id            = module.secondary_kms.key_arn
  
  tags = merge(local.common_tags, {
    Name        = local.resource_names.backup_replication
    Purpose     = "Cross-region automated backup replication"
    Source      = var.primary_region
    Destination = var.secondary_region
    Description = "Automated cross-region backup replication for Oracle RDS"
  })
  
  depends_on = [
    module.oracle_primary,
    module.secondary_kms
  ]
}