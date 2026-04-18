########################################
# examples/complete/efs.tf
#
# EFS file system for the api tier.
# Mounted at /app/uploads inside api containers for shared upload storage.
# Mount targets placed in data subnets; access restricted to api SG via NFS.
########################################

module "efs" {
  source = "tfe.com/efs/aws"

  name           = "${var.environment}-api-uploads"
  creation_token = "${var.environment}-api-uploads"
  kms_key_arn    = module.efs_kms.key_arn

  mount_targets = {
    subnets           = data.aws_subnets.data.ids
    security_group_id = module.sg_efs.security_group_id
  }

  # Allow api task role to mount and write
  efs_file_system_policy = [
    {
      sid = "APITierAccess"
      actions = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      principals = [{
        type        = "AWS"
        identifiers = [module.iam_api.task_role_arn]
      }]
      condition = [{
        test     = "Bool"
        variable = "elasticfilesystem:AccessedViaMountTarget"
        values   = ["true"]
      }]
    }
  ]

  tags = merge(var.tags, { tier = "api" })
}

########################################
# KMS key for EFS encryption at rest
########################################

module "efs_kms" {
  source = "tfe.com/kms/aws"

  enable_creation         = true
  enable_key              = true
  key_name                = "${var.environment}-api-efs-kms"
  description             = "KMS key for api tier EFS encryption"
  deletion_window_in_days = 14

  key_statements = [
    {
      sid    = "EFSService"
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
    },
    {
      sid    = "APITaskRole"
      effect = "Allow"
      principals = [{
        type        = "AWS"
        identifiers = [module.iam_api.task_role_arn]
      }]
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  ]

  tags = merge(var.tags, { tier = "api" })
}
