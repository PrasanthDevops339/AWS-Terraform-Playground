# Local values for active exceptions and allowlist
locals {
  # Filter active exceptions (not expired)
  today = formatdate("YYYY-MM-DD", timestamp())
  
  active_exceptions = {
    for account_id, expiry_date in var.exception_accounts :
    account_id => expiry_date
    if timecmp(expiry_date, local.today) >= 0
  }

  expired_exceptions = {
    for account_id, expiry_date in var.exception_accounts :
    account_id => expiry_date
    if timecmp(expiry_date, local.today) < 0
  }

  # Build complete allowlist
  allowlist = concat(
    [var.ops_publisher_account],
    var.vendor_publisher_accounts,
    keys(local.active_exceptions)
  )

  # Sort for consistency
  sorted_allowlist = sort(local.allowlist)
}

# Declarative Policy for EC2
resource "aws_organizations_policy" "declarative_ec2" {
  name        = "ami-governance-declarative-policy"
  description = "AMI Governance - Restrict EC2 launches to approved AMI publishers"
  type        = "DECLARATIVE_POLICY_EC2"

  content = jsonencode({
    ec2 = {
      "@@operators_allowed_for_child_policies" = ["@@none"]

      ec2_attributes = {
        image_block_public_access = {
          "@@operators_allowed_for_child_policies" = ["@@none"]
          state                                    = "block_new_sharing"
        }

        allowed_images_settings = {
          "@@operators_allowed_for_child_policies" = ["@@none"]
          state                                    = var.enforcement_mode

          image_criteria = {
            criteria_1 = {
              allowed_image_providers = local.sorted_allowlist
            }
          }

          exception_message = "AMI not approved for use in this organization. Only images from approved publisher accounts are permitted. To request an exception, submit a ticket at: ${var.exception_request_url} with business justification, duration needed (max 90 days), and security approval."
        }
      }
    }
  })

  tags = merge(
    var.tags,
    {
      Name       = "ami-governance-declarative-policy"
      PolicyType = "DECLARATIVE_POLICY_EC2"
    }
  )
}

# Attach Declarative Policy to Organization Root
resource "aws_organizations_policy_attachment" "declarative_ec2" {
  policy_id = aws_organizations_policy.declarative_ec2.id
  target_id = var.org_root_id
}

# Service Control Policy
resource "aws_organizations_policy" "scp" {
  name        = "scp-ami-guardrail"
  description = "AMI Governance SCP - Deny non-approved AMIs and AMI creation"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyEC2LaunchWithNonApprovedAMIs"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:RequestSpotInstances",
          "ec2:RunScheduledInstances"
        ]
        Resource = "arn:aws:ec2:*::image/*"
        Condition = {
          StringNotEquals = {
            "ec2:Owner" = local.sorted_allowlist
          }
        }
      },
      {
        Sid    = "DenyAMICreationAndSideload"
        Effect = "Deny"
        Action = [
          "ec2:CreateImage",
          "ec2:CopyImage",
          "ec2:RegisterImage",
          "ec2:ImportImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyPublicAMISharing"
        Effect = "Deny"
        Action = [
          "ec2:ModifyImageAttribute"
        ]
        Resource = "arn:aws:ec2:*::image/*"
        Condition = {
          StringEquals = {
            "ec2:Add/group" = "all"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name       = "scp-ami-guardrail"
      PolicyType = "SERVICE_CONTROL_POLICY"
    }
  )
}

# Attach SCP to Organization Root
resource "aws_organizations_policy_attachment" "scp" {
  policy_id = aws_organizations_policy.scp.id
  target_id = var.org_root_id
}

# Check for expired exceptions
resource "null_resource" "check_expired_exceptions" {
  triggers = {
    expired_count = length(local.expired_exceptions)
    expired_list  = jsonencode(local.expired_exceptions)
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ ${length(local.expired_exceptions)} -gt 0 ]; then
        echo "⚠️  WARNING: Found ${length(local.expired_exceptions)} EXPIRED exceptions:"
        echo '${jsonencode(local.expired_exceptions)}' | jq -r 'to_entries[] | "  • Account: \(.key) expired on \(.value)"'
        echo ""
        echo "Please remove expired exceptions from variables.tf"
        exit 1
      fi
    EOT
    interpreter = ["bash", "-c"]
  }
}
