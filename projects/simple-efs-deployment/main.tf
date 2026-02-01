###############################################################################
# Simple EFS Deployment
# This configuration deploys:
# - KMS key for EFS encryption
# - Security group for EFS access
# - EFS file system with mount targets
###############################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"

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
# EFS File System
###############################################################################

module "efs" {
  source = "../../Terrafrom-AWS-Prasanth/terraform-aws-efs"

  name           = "${local.name_prefix}-efs"
  creation_token = "${local.name_prefix}-efs"
  kms_key_arn    = module.kms.key_arn

  # Performance settings
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  # Backup policy
  enable_backup_policy = var.enable_backup

  # Mount targets in each subnet
  mount_targets = {
    subnets           = data.aws_subnets.efs.ids
    security_group_id = [aws_security_group.efs.id]
  }

  # Lifecycle policy - transition to IA after 30 days
  lifecycle_policy = {
    transition_to_ia                    = ["AFTER_30_DAYS"]
    transition_to_primary_storage_class = ["AFTER_1_ACCESS"]
  }

  tags = local.common_tags
}
