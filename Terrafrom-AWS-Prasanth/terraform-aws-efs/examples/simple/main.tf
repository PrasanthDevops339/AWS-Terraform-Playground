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
  source = "../../."

  name           = "efs_simple_example"
  creation_token = "efs-simple-example"
  kms_key_arn    = module.kms.key_arn

  #mount target
  mount_targets = {
    subnets           = data.aws_subnets.data.ids
    security_group_id = ["${module.sg.security_group_id}"]
  }

  tags = local.backup_tags
}

#--- supporting modules ---#

# kms key for encryption
module "kms" {
  source = "tfe.com/kms/aws"

  enable_creation = true # Set to false to mark key for deletion
  enable_key      = true # Set to false to disable key
  key_name        = "kms-key-simple-efs"
  description     = "This will be used efs"
  deletion_window_in_days = 8 # Must be between 7 and 30 days (defaults to 7 days)

  key_statements = [
    {
      sid    = "EFSPermissions"
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
    }
  ]
}

# security group for EFS
module "sg" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "sg_efs-simple_example"
  description = "sg for efs "
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 2049
      to_port     = 2049
      ip_protocol = "tcp"
      cidr_ipv4   = "10.223.0.0/20"
      description = "Allow ingress EFS traffic from app az1"
    },
    {
      from_port   = 2049
      to_port     = 2049
      ip_protocol = "tcp"
      cidr_ipv4   = "10.223.64.0/20"
      description = "Allow ingress EFS traffic from app az2"
    },
    {
      from_port   = 2049
      to_port     = 2049
      ip_protocol = "tcp"
      cidr_ipv4   = "10.223.128.0/20"
      description = "Allow ingress EFS traffic from app az3"
    }
  ]
}
