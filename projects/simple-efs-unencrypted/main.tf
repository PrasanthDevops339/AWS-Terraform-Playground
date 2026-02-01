###############################################################################
# Simple EFS Deployment - UNENCRYPTED
# 
# WARNING: This EFS is NOT encrypted at rest. 
# Use only for non-sensitive data or testing purposes.
#
# This configuration deploys:
# - Security group for EFS access
# - EFS file system (unencrypted) with mount targets
###############################################################################

locals {
  name_prefix   = "${var.project_name}-${var.environment}"
  account_alias = data.aws_iam_account_alias.current.account_alias

  backup_tags = {
    "ops:backupschedule1" = var.enable_backup ? "daily" : "none"
    "ops:backupschedule2" = "none"
    "ops:backupschedule3" = "none"
    "ops:backupschedule4" = "none"
    "ops:drschedule1"     = "none"
    "ops:drschedule2"     = "none"
    "ops:drschedule3"     = "none"
    "ops:drschedule4"     = "none"
  }

  common_tags = merge(
    local.backup_tags,
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
    }
  )
}

###############################################################################
# Security Group for EFS
###############################################################################

resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = data.aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-efs-sg"
    }
  )
}

# Ingress rule for NFS traffic (port 2049)
resource "aws_vpc_security_group_ingress_rule" "efs_nfs" {
  for_each = { for idx, cidr in var.allowed_cidrs : idx => cidr }

  security_group_id = aws_security_group.efs.id
  description       = "Allow NFS traffic from ${each.value}"
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value

  tags = local.common_tags
}

# Egress rule - allow all outbound
resource "aws_vpc_security_group_egress_rule" "efs_all" {
  security_group_id = aws_security_group.efs.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.common_tags
}

###############################################################################
# EFS File System - UNENCRYPTED
###############################################################################

resource "aws_efs_file_system" "main" {
  creation_token   = "${local.name_prefix}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  
  # NO ENCRYPTION
  encrypted = false

  # Lifecycle policy - transition to IA after 30 days
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.account_alias}-${local.name_prefix}-efs"
    }
  )
}

###############################################################################
# EFS Mount Targets
###############################################################################

resource "aws_efs_mount_target" "main" {
  count = length(data.aws_subnets.efs.ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = data.aws_subnets.efs.ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

###############################################################################
# EFS Backup Policy
###############################################################################

resource "aws_efs_backup_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = var.enable_backup ? "ENABLED" : "DISABLED"
  }
}
