#########################
# examples/complete/efs.tf
#########################

locals {
  backup_tags = {
    "ops:backupschedule1" = "none"
    "ops:backupschedule2" = "none"
    "ops:backupschedule3" = "none"
    "ops:backupschedule4" = "none"
    "ops:drschedule1"     = "none"
    "ops:drschedule2"     = "none"
    "ops:drschedule3"     = "none"
    "ops:drschedule4"     = "none"
  }
}

module "efs" {
  source = "tfe.com/efs/aws"

  name           = "efs_simple_example"
  creation_token = "efs-simple-example"
  kms_key_arn    = module.efs_kms.key_arn

  # mount target
  mount_targets = {
    subnets          = data.aws_subnets.data.ids
    security_group_id = "${module.sg.security_group_id}"
  }

  # file system policy
  efs_file_system_policy = [
    {
      sid      = "Example"
      actions  = [
        "elasticfilesystem:ClientRootAccess",
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
      ]

      principals = [{
        type        = "AWS"
        identifiers = [
          module.iam_role.iam_role_arn
        ]
      }]

      condition = [{
        test     = "Bool"
        variable = "elasticfilesystem:AccessedViaMountTarget"
        values   = ["true"]
      }]
    }
  ]

  tags = local.backup_tags
}

# -- supporting modules -- #

# kms key for encryption
module "efs_kms" {
  source = "tfe.com/kms/aws"

  enable_creation        = true  # Set to false to mark key for deletion
  enable_key             = true  # Set to false to disable key
  key_name               = "kms-key-simple-efs"
  description            = "This will be used efs"
  deletion_window_in_days = 8    # Must be between 7 and 30 days (defaults to 7 days)

  key_statements = [
    {
      sid     = "EFSPermissions"
      effect  = "Allow"
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
        "kms:DescribeKey",
      ]
      resources = ["*"]
    },
    {
      sid     = "ECSRolePermissions"
      effect  = "Allow"
      principals = [{
        type        = "AWS"
        identifiers = [module.iam_role.iam_role_arn]
      }]
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  ]
}

# security group for EFS
module "sg" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "sg_efs-simple_example"
  description = "sg for efs"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 2049
      to_port     = 2049
      ip_protocol = "tcp"
      cidr_ipv4   = "10.0.0.0/8"
      description = "Allow ingress EFS traffic"
    }
  ]
}
