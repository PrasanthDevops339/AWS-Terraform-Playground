##################################################
# Local Variables - Process exceptions and build allowlists
##################################################

locals {
  # Current date for comparison
  current_date = timestamp()
  current_date_str = formatdate("YYYY-MM-DD", local.current_date)
  
  # Filter out expired exception accounts
  active_exceptions = {
    for account, expiry in var.exception_accounts :
    account => expiry
    if timecmp(expiry, local.current_date_str) >= 0
  }
  
  # Combine approved accounts with active exceptions
  all_allowed_ami_owners = concat(
    var.approved_ami_owner_accounts,
    keys(local.active_exceptions)
  )
  
  # Policy names
  declarative_policy_name = "${var.policy_name_prefix}-declarative-policy"
  scp_policy_name         = "${var.policy_name_prefix}-scp"
  
  # Use workload OUs if specified, otherwise use all OUs
  scp_target_ou_ids = length(var.workload_ou_ids) > 0 ? var.workload_ou_ids : var.org_root_or_ou_ids
}

##################################################
# EC2 Declarative Policy - Image Block Public Access
##################################################

resource "aws_organizations_policy" "ami_declarative_policy" {
  count = var.enable_declarative_policy ? 1 : 0
  
  name        = local.declarative_policy_name
  description = "Declarative policy to block public AMI sharing and restrict AMI discovery to approved publishers"
  type        = "DECLARATIVE_POLICY_EC2"
  
  content = jsonencode({
    policies = {
      image_block_public_access_policy = {
        image_block_public_access = {
          statement = {
            block_public_access_value = {
              "@operator" = "string_equals"
              "@value"    = "block_new_sharing"
            }
          }
        }
      }
      
      allowed_images_settings_policy = {
        allowed_images_settings = {
          statement = {
            discover_allowed_image_providers = {
              enforcement_mode = {
                "@operator" = "string_equals"
                "@value"    = var.policy_mode
              }
              
              allowed_image_providers = {
                "@operator" = "for_all_values:string_equals"
                "@value"    = local.all_allowed_ami_owners
              }
              
              exception_message = {
                "@value" = var.exception_message
              }
            }
          }
        }
      }
    }
  })
  
  tags = merge(
    var.tags,
    {
      Name        = local.declarative_policy_name
      PolicyType  = "Declarative-EC2"
      Version     = "1.0"
      LastUpdated = local.current_date_str
    }
  )
}

resource "aws_organizations_policy_attachment" "ami_declarative_policy_attachment" {
  for_each = var.enable_declarative_policy ? toset(var.org_root_or_ou_ids) : toset([])
  
  policy_id = aws_organizations_policy.ami_declarative_policy[0].id
  target_id = each.value
}

##################################################
# Service Control Policy (SCP) - AMI Launch Restrictions
##################################################

resource "aws_organizations_policy" "ami_scp_policy" {
  count = var.enable_scp_policy ? 1 : 0
  
  name        = local.scp_policy_name
  description = "SCP to enforce approved AMI usage and prevent AMI creation in workload accounts"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Deny EC2 instance launches with non-approved AMIs
      {
        Sid    = "DenyEC2LaunchWithUnapprovedAMI"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:RequestSpotInstances",
          "ec2:RequestSpotFleet",
          "autoscaling:CreateLaunchConfiguration",
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "ec2:Owner" = local.all_allowed_ami_owners
          }
        }
      },
      
      # Deny AMI creation to prevent app teams from baking AMIs
      {
        Sid    = "DenyAMICreation"
        Effect = "Deny"
        Action = [
          "ec2:CreateImage",
          "ec2:CopyImage",
          "ec2:RegisterImage",
          "ec2:ImportImage",
          "ec2:ImportSnapshot"
        ]
        Resource = "*"
      },
      
      # Deny AMI sharing modifications to prevent workarounds
      {
        Sid    = "DenyAMISharing"
        Effect = "Deny"
        Action = [
          "ec2:ModifyImageAttribute",
          "ec2:ModifySnapshotAttribute"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:Attribute" = ["launchPermission", "createVolumePermission"]
          }
        }
      }
    ]
  })
  
  tags = merge(
    var.tags,
    {
      Name        = local.scp_policy_name
      PolicyType  = "SCP"
      Version     = "1.0"
      LastUpdated = local.current_date_str
    }
  )
}

resource "aws_organizations_policy_attachment" "ami_scp_policy_attachment" {
  for_each = var.enable_scp_policy ? toset(local.scp_target_ou_ids) : toset([])
  
  policy_id = aws_organizations_policy.ami_scp_policy[0].id
  target_id = each.value
}

##################################################
# CloudWatch Alarm for Exception Expiry Monitoring
##################################################

# Create SNS topic for exception expiry notifications
resource "aws_sns_topic" "ami_exception_expiry" {
  name = "${var.policy_name_prefix}-exception-expiry-notifications"
  
  tags = merge(
    var.tags,
    {
      Name    = "${var.policy_name_prefix}-exception-expiry-notifications"
      Purpose = "Alert when AMI policy exceptions are nearing expiry"
    }
  )
}

##################################################
# SSM Parameter for Exception Tracking
##################################################

resource "aws_ssm_parameter" "ami_exceptions" {
  name        = "/${var.policy_name_prefix}/active-exceptions"
  description = "Active AMI policy exceptions with expiry dates"
  type        = "String"
  value = jsonencode({
    last_updated       = local.current_date_str
    active_exceptions  = local.active_exceptions
    expired_exceptions = {
      for account, expiry in var.exception_accounts :
      account => expiry
      if timecmp(expiry, local.current_date_str) < 0
    }
  })
  
  tags = merge(
    var.tags,
    {
      Name          = "AMI Policy Exceptions"
      AutoGenerated = "true"
    }
  )
}
