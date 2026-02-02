###############################################################################
# Simple EFS Deployment - WITH INSUFFICIENT POLICY
# 
# WARNING: This EFS has a resource policy but it does NOT enforce TLS in transit
# for EFS client actions. This is a non-compliant configuration.
#
# This configuration deploys:
# - Security group for EFS access
# - EFS file system (encrypted at rest) with mount targets
# - EFS file system policy that does NOT properly enforce TLS for client actions
#
# NON-COMPLIANCE REASON:
# The policy denies access when SecureTransport=false, BUT only for S3-like actions
# (not EFS client actions like ClientMount, ClientWrite, ClientRootAccess).
# This demonstrates a misconfigured policy that appears to enforce TLS but doesn't
# actually protect EFS client operations.
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
# KMS Key for EFS Encryption
###############################################################################

module "kms" {
  source = "../../Terrafrom-AWS-Prasanth/terraform-aws-kms"

  enable_creation         = true
  enable_key              = true
  key_name                = "${local.name_prefix}-efs-key"
  description             = "KMS key for EFS encryption - ${local.name_prefix}"
  deletion_window_in_days = 7

  key_statements = [
    {
      sid    = "EnableKeyAdministration"
      effect = "Allow"

      principals = [{
        type        = "AWS"
        identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/operation-admin-role"]
      }]

      actions = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
        "kms:ReplicateKey",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant"
      ]

      resources = ["*"]
    },
    {
      sid    = "EFSServicePermissions"
      effect = "Allow"

      principals = [{
        type        = "Service"
        identifiers = ["elasticfilesystem.amazonaws.com"]
      }]

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey"
      ]

      resources = ["*"]

      conditions = [{
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }]
    },
    {
      sid    = "AllowEFSViaService"
      effect = "Allow"

      principals = [{
        type        = "AWS"
        identifiers = ["*"]
      }]

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey"
      ]

      resources = ["*"]

      conditions = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = ["elasticfilesystem.${data.aws_region.current.name}.amazonaws.com"]
        },
        {
          test     = "StringEquals"
          variable = "kms:CallerAccount"
          values   = [data.aws_caller_identity.current.account_id]
        }
      ]
    }
  ]

  tags = local.common_tags
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
# EFS File System - ENCRYPTED AT REST
###############################################################################

resource "aws_efs_file_system" "main" {
  creation_token   = "${local.name_prefix}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  
  # Encryption at rest enabled with customer-managed KMS key
  encrypted  = true
  kms_key_id = module.kms.key_arn

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
# EFS File System Policy - INSUFFICIENT (NON-COMPLIANT)
###############################################################################
# This policy demonstrates a common misconfiguration:
# - It has a Deny statement with SecureTransport=false condition
# - BUT the actions it denies are NOT EFS client actions
# - It denies generic "Describe" actions instead of ClientMount/ClientWrite/ClientRootAccess
# - Therefore, it does NOT enforce TLS for actual EFS client operations
# - The Lambda function will correctly identify this as NON_COMPLIANT
###############################################################################

resource "aws_efs_file_system_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  # INSUFFICIENT POLICY - Does NOT enforce TLS for EFS client actions
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        # WRONG ACTIONS - These are NOT EFS client actions!
        # This policy only denies DescribeFileSystem when SecureTransport=false
        # It does NOT deny ClientMount, ClientWrite, or ClientRootAccess
        Action = [
          "elasticfilesystem:DescribeFileSystem",
          "elasticfilesystem:DescribeAccessPoints"
        ]
        Resource = aws_efs_file_system.main.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.main.arn
      }
    ]
  })
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
