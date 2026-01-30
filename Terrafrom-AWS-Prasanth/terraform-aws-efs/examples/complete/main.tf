locals {
  user_data = <<-EOT
  #!/bin/bash

  # install mount helper
  echo "installing mount helper"
  sudo yum install -y amazon-efs-utils
  # Mount EFS
  mkdir efs
  echo "created efs folder"
  sudo mount -t efs -o tls,iam "${module.efs.id}" efs/
  echo "run till here..."
  EOT

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

  patch_tags = {
    "PatchGroup" = "a"
  }
}

module "efs" {
  source = "../../.."

  name           = "efs_complete_test"
  creation_token = "efs-for-test"
  kms_key_arn    = module.kms.key_arn
  tags           = merge(local.backup_tags, local.patch_tags)

  # performance and throughput
  performance_mode               = "maxIO"
  throughput_mode                = "provisioned"
  provisioned_throughput_in_mibps = 256

  # lifecycle policy
  lifecycle_policy = {
    transition_to_ia                    = ["AFTER_30_DAYS"]
    transition_to_primary_storage_class = ["AFTER_1_ACCESS"]
  }

  # file system policy
  efs_file_system_policy = [
    {
      sid = "Example"
      actions = [
        "elasticfilesystem:ClientRootAccess",
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite"
      ]

      principals = [{
        type        = "AWS"
        identifiers = [
          module.iam.iam_role_arn
        ]
      }]

      condition = [{
        test     = "Bool"
        variable = "elasticfilesystem:AccessedViaMountTarget"
        values   = ["true"]
      }]
    }
  ]

  # mount target
  mount_targets = {
    subnets           = data.aws_subnets.data.ids
    security_group_id = ["${module.sg.security_group_id}"]
  }

  # access point
  access_points = {
    posix_example = {
      name = "posix-example"
      posix_user = {
        gid            = 1001
        uid            = 1001
        secondary_gids = [1002]
      }
    }

    root_example = {
      root_directory = {
        path = "/example"
        creation_info = {
          owner_gid   = 1001
          owner_uid   = 1001
          permissions = "755"
        }
      }
    }
  }

  # Replication configuration
  # PLACEHOLDER: remaining replication configuration content not fully provided in screenshots.
}

#--- supporting modules ---#

# kms key for encryption
module "kms" {
  source = "tfe.com/kms/aws"

  key_name    = "efs-key"
  description = "kms key for efs encryption"

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
    },
    {
      sid    = "EC2InstanceProfilePermissions"
      effect = "Allow"

      principals = [{
        type        = "AWS"
        identifiers = [module.iam.iam_role_arn]
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

module "ec2_efs_test1" {
  source = "tfe.com/ec2/aws"

  ec2_name            = "efs_testing_mount1"
  instance_type       = "t2.micro"
  ami                 = "ami-037774efca2da0726"
  subnet_type         = "app"
  vpc_security_group_ids = [module.sgec2.security_group_id]
  user_data_base64    = base64encode(local.user_data)
  iam_instance_profile = module.iam.iam_instance_profile_name

  root_block_device = [
    {
      volume_type = "gp3"
      throughput  = 200
      volume_size = 80
      encrypted   = true
      kms_key_id  = module.kms.key_arn
    }
  ]

  depends_on = [
    module.efs.mount_targets
  ]

  tags = merge(local.backup_tags, local.patch_tags)

  volume_tags = merge(local.backup_tags, local.patch_tags, {
    # PLEASE DO NOT USE SHOWN COSTCENTER TAG VALUE
    "finops:application"  = "platform_core_services"
    "finops:portfolio"    = "Technology Delivery"
    "finops:costcenter"   = "DTD04"
    "finops:owner"        = "my_team_DL@example.com"
    "admin:environment"   = "dev"
  })
}

#second ec2 for efs mount
module "ec2_efs_test2" {
  source = "tfe.com/ec2/aws"

  ec2_name            = "efs_testing_mount2"
  instance_type       = "t2.micro"
  ami                 = "ami-037774efca2da0726"
  subnet_type         = "app"
  vpc_security_group_ids = [module.sgec2.security_group_id]
  user_data_base64    = base64encode(local.user_data)
  iam_instance_profile = module.iam.iam_instance_profile_name

  root_block_device = [
    {
      volume_type = "gp3"
      throughput  = 200
      volume_size = 80
      encrypted   = true
      kms_key_id  = module.kms.key_arn
    }
  ]

  depends_on = [
    module.efs.mount_targets
  ]

  tags = merge(local.backup_tags, local.patch_tags)

  volume_tags = merge(local.backup_tags, local.patch_tags, {
    # PLEASE DO NOT USE SHOWN COSTCENTER TAG VALUE
    "finops:application"  = "platform_core_services"
    "finops:portfolio"    = "Technology Delivery"
    "finops:costcenter"   = "DTD04"
    "finops:owner"        = "my_team_DL@example.com"
    "admin:environment"   = "dev"
  })
}

#security group for ec2
module "sgec2" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "sg_efs_mount"
  description = "sg for ec2 "
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "10.223.32.0/20"
      description = "Allow ingress 443 traffic from web az1"
    },
    {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "10.223.96.0/20"
      description = "Allow ingress 443 traffic from web az2"
    },
    {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "10.223.160.0/20"
      description = "Allow ingress 443 traffic from web az3"
    }
  ]

  egress_rules = [
    {
      description = "egress from ec2"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  ]
}

module "sg" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "sg_efs-ec2mount_example"
  description = "sg for ec2mount "
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

# kms key for replica
module "efs_replica_key" {
  source = "tfe.com/kms/aws"

  key_name        = "efs-replica-key"
  description     = "kms key for efs replica encryption"
  primary_key_arn = module.kms.key_arn

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
    },
    {
      sid    = "EC2InstanceProfilePermissions"
      effect = "Allow"

      principals = [{
        type        = "AWS"
        identifiers = [module.iam.iam_role_arn]
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

  providers = {
    aws = aws.us_east_1
  }
}

module "iam" {
  source = "tfe.com/iam/aws"

  trusted_role_arns     = ["111111111111"]
  trusted_role_services = ["ec2.amazonaws.com"]

  create_role             = true
  create_policy           = true
  create_instance_profile = true

  role_name        = "simple-ec2-test-role"
  policy_name      = "simple-ec2-policy-test-efs"
  description      = "ec2 policy which will be assume by deployment account"
  policy           = data.aws_iam_policy_document.policy_doc.json
}
