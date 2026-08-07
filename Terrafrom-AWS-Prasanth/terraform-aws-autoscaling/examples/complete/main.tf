locals {
  application_name = "complete-asg-${random_string.example_suffix.result}"

  default_tags = {
    "finops:application" = "test-application"
    "finops:portfolio"   = "technology_delivery"
    "finops:costcenter"  = "XXXX"
    "finops:owner"       = "John Doe"
    "admin:environment"  = "dev"
  }

  patch_tags = {
    PatchGroup = "asg"
  }

  backup_tags = {
    "ops:backupschedule1" = "hourly1day"
    "ops:backupschedule2" = "None"
    "ops:backupschedule3" = "None"
    "ops:backupschedule4" = "None"
    "ops:drschedule1"     = "hourly1dayuseast2"
    "ops:drschedule2"     = "None"
    "ops:drschedule3"     = "None"
    "ops:drschedule4"     = "None"
  }
}

resource "random_string" "example_suffix" {
  length  = 3
  numeric = false
  special = false
  upper   = false
}

module "autoscaling" {
  source = "../.."

  create_asg             = true
  create_lt              = true
  instance_type          = "t2.small"
  launch_template_name   = "${local.application_name}-lt"
  template_description   = "ASG complete test launch template"
  ami_id                 = data.aws_ami.rhel8.id
  autoscaling_group_name = local.application_name
  subnet_type            = "app"
  iam_instance_profile   = module.asg_complete_profile.iam_instance_profile_name
  min_size               = 1
  max_size               = 2
  desired_capacity       = 2
  health_check_type      = "EC2"
  vpc_security_group_ids = [module.security_group.id]
  kms_key_id             = module.asg_primary_key.key_arn

  block_device_mappings = [
    {
      # Root volume
      device_name = "/dev/xvda"
      no_device   = 0

      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 20
        volume_type           = "gp2"
      }
    }
  ]

  asg_tags                     = local.default_tags
  asg_tags_propagate_at_launch = true
  default_cooldown             = 300

  scaling_policies = {
    simple_scaling_testing = {
      policy_type        = "SimpleScaling"
      scaling_adjustment = 1
      adjustment_type    = "ChangeInCapacity"
      cooldown           = 300
    }
  }

  # Uncomment arguments below for ELB-related configurations.
  # min_elb_capacity          = 1
  # wait_for_elb_capacity     = 1
  # wait_for_capacity_timeout = "15m"

  tag_specifications = [
    {
      resource_type = "volume"
      tags = merge(
        { Name = "${local.application_name}-volume" },
        local.default_tags,
        local.backup_tags
      )
    },
    {
      resource_type = "instance"
      tags = merge(
        { Name = "${local.application_name}-instance" },
        local.default_tags,
        local.patch_tags,
        local.backup_tags
      )
    }
  ]
}

module "autoscaling_use1" {
  source = "../.."

  region                  = "us-east-1"
  create_asg              = true
  create_lt               = true
  instance_type           = "t2.small"
  launch_template_name    = "${local.application_name}-use1-lt"
  template_description    = "ASG complete test launch template in us-east-1"
  ami_id                  = data.aws_ami.rhel8_use1.id
  autoscaling_group_name  = "${local.application_name}-use1"
  subnet_type             = "app"
  iam_instance_profile    = module.asg_complete_profile.iam_instance_profile_name
  min_size                = 1
  max_size                = 1
  desired_capacity        = 1
  health_check_type       = "EC2"
  vpc_security_group_ids  = [module.security_group_use1.id]
  kms_key_id              = module.asg_primary_key.key_arn
  asg_tags                = local.default_tags
  default_cooldown        = 300

  # Opted out of ASG-pattern patching, so fixed 1/1/1 capacity stays valid.
  enable_patch_group_asg = false
}

module "asg_complete_profile" {
  source = "tfe.prasanth.com/prasanth/iam/aws"

  trusted_role_arns     = [var.account_id]
  trusted_role_services = ["ssm.amazonaws.com"]

  create_instance_profile = true

  create_policy = true
  policy_name   = "${local.application_name}-policy"
  policy = templatefile("${path.module}/asg_instance_profile_policy.json", {
    account_id = var.account_id
  })

  create_role = true
  role_name   = "${local.application_name}-role"
}

module "security_group" {
  source = "tfe.prasanth.com/prasanth/security-group/aws"

  sg_name     = "${local.application_name}-sg"
  description = "Complete ASG security group"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.web_az1_cidr
      description = "Allow from web AZ1 subnet"
    },
    {
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.web_az2_cidr
      description = "Allow from web AZ2 subnet"
    },
    {
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.web_az3_cidr
      description = "Allow from web AZ3 subnet"
    }
  ]

  egress_rules = [
    {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow to all"
    },
    {
      from_port   = 5670
      to_port     = 5670
      cidr_ipv4   = var.tripwire_cidr
      description = "Allow Tripwire port"
    }
  ]
}

module "security_group_use1" {
  source = "tfe.prasanth.com/prasanth/security-group/aws"

  sg_name     = "${local.application_name}-use1-sg"
  description = "Complete ASG security group in us-east-1"
  vpc_id      = data.aws_vpc.main_use1.id

  ingress_rules = []
  egress_rules = [
    {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow to all"
    }
  ]
}

module "asg_primary_key" {
  source = "tfe.prasanth.com/prasanth/kms/aws"

  key_name    = local.application_name
  description = "ASG key example showing various configurations available"

  key_statements = [
    {
      sid = "ASG"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
      principals = [
        {
          type = "AWS"
          identifiers = [
            "arn:aws:iam::${var.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          ]
        }
      ]
    },
    {
      sid = "Attach to persistent ASG resources"
      actions = [
        "kms:CreateGrant"
      ]
      resources = ["*"]
      principals = [
        {
          type = "AWS"
          identifiers = [
            "arn:aws:iam::${var.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          ]
        }
      ]
    }
  ]
}
