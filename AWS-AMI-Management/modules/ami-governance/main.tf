# ============================================================================
# AMI GOVERNANCE MODULE
# ============================================================================
# Reusable Terraform module for AWS Organizations AMI governance policies
# Creates both declarative policy and SCP with automatic exception management

# ============================================================================
# LOCAL VARIABLES
# ============================================================================
# Local values calculate the active exceptions and build the complete allowlist
# of approved AMI publishers that will be used in both policies

locals {
  # Get today's date in YYYY-MM-DD format for exception expiry comparison
  # Uses timestamp() function to get current time, formatdate() to format it
  today = formatdate("YYYY-MM-DD", timestamp())
  
  # Filter exception_accounts map to only include accounts with future expiry dates
  # Loop through all exception_accounts, keep only if expiry_date >= today
  # timecmp() returns: -1 if date1 < date2, 0 if equal, 1 if date1 > date2
  active_exceptions = {
    for account_id, expiry_date in var.exception_accounts : # Iterate over exception map
    account_id => expiry_date                               # Keep the account => date mapping
    if timecmp(expiry_date, local.today) >= 0              # Only if expiry date is today or future
  }

  # Build a separate map of EXPIRED exceptions (expiry_date < today)
  # This is used to fail the deployment if expired exceptions exist
  expired_exceptions = {
    for account_id, expiry_date in var.exception_accounts : # Iterate over exception map
    account_id => expiry_date                               # Keep the account => date mapping
    if timecmp(expiry_date, local.today) < 0               # Only if expiry date is in the past
  }

  # Build the complete allowlist by combining:
  # 1. Ops golden AMI publisher account (single account in a list)
  # 2. Vendor publisher accounts (list of approved vendors)
  # 3. Active exception accounts (keys from active_exceptions map)
  allowlist = concat(
    [var.ops_publisher_account],       # Wrap single account in list for concat
    var.vendor_publisher_accounts,     # Already a list
    keys(local.active_exceptions)      # Extract account IDs (keys) from exceptions map
  )

  # Sort the allowlist alphabetically for consistency
  # This ensures policy updates are deterministic and easier to diff
  sorted_allowlist = sort(local.allowlist)
}

# ============================================================================
# DECLARATIVE POLICY FOR EC2
# ============================================================================
# AWS Organizations Declarative Policy for EC2 - native AWS enforcement
# Requires AWS provider >= 5.0 for DECLARATIVE_POLICY_EC2 type support
# This policy controls which AMI publishers can be used to launch EC2 instances

resource "aws_organizations_policy" "declarative_ec2" {
  name        = var.declarative_policy_name                # Policy name shown in AWS console
  description = "AMI Governance - Restrict EC2 launches to approved AMI publishers"
  type        = "DECLARATIVE_POLICY_EC2"                   # Native declarative policy type (not SCP)

  # Convert HCL map to JSON policy document
  # jsonencode() ensures proper JSON formatting
  content = jsonencode({
    ec2 = { # Top-level ec2 namespace for declarative policy
      # Prevent child OUs/accounts from overriding this policy
      "@@operators_allowed_for_child_policies" = ["@@none"]

      ec2_attributes = { # EC2-specific attribute controls
        # Block public AMI sharing at the organization level
        image_block_public_access = {
          "@@operators_allowed_for_child_policies" = ["@@none"] # No child overrides
          state                                    = "block_new_sharing" # Prevent new public sharing
        }

        # Control which AMI publishers are allowed for EC2 launches
        allowed_images_settings = {
          "@@operators_allowed_for_child_policies" = ["@@none"] # No child overrides
          state                                    = var.enforcement_mode # audit_mode or enabled

          # Define criteria for allowed AMIs
          image_criteria = {
            criteria_1 = { # Can have multiple criteria (criteria_1, criteria_2, etc.)
              allowed_image_providers = local.sorted_allowlist # List of approved AWS account IDs
            }
          }

          # User-friendly error message when non-approved AMI is used
          # This appears in AWS console and API responses
          exception_message = "AMI not approved for use in this organization. Only images from approved publisher accounts are permitted. To request an exception, submit a ticket at: ${var.exception_request_url} with business justification, duration needed (max 90 days), and security approval."
        }
      }
    }
  })

  # Merge default tags with policy-specific tags
  tags = merge(
    var.tags,                                          # Base tags from variables (ManagedBy, Feature, etc.)
    {
      Name        = var.declarative_policy_name        # Override Name tag
      PolicyType  = "DECLARATIVE_POLICY_EC2"           # Tag indicating policy type
      Environment = var.environment                    # Environment tag (dev/prd)
    }
  )
}

# ==========================================================================
# POLICY ATTACHMENTS - DECLARATIVE POLICY
# ==========================================================================
# Attach the declarative policy to specified target IDs (Root/OUs/Accounts)
# for_each creates one attachment per target ID

resource "aws_organizations_policy_attachment" "declarative_ec2" {
  for_each = toset(var.target_ids) # Convert list to set for for_each iteration

  policy_id = aws_organizations_policy.declarative_ec2.id # Reference to policy created above
  target_id = each.value                                   # OU/Root/Account ID from target_ids list
}

# ==========================================================================
# SERVICE CONTROL POLICY (SCP)
# ==========================================================================
# Traditional SCP acts as an IAM permission boundary - second layer of defense
# Even if declarative policy is bypassed, SCP blocks the API calls
# SCP evaluates at IAM level, blocking actions regardless of identity

resource "aws_organizations_policy" "scp" {
  name        = var.scp_policy_name                                        # SCP name in AWS console
  description = "AMI Governance SCP - Deny non-approved AMIs and AMI creation" # Describes SCP purpose
  type        = "SERVICE_CONTROL_POLICY"                                   # Traditional SCP type

  # SCP policy document in standard IAM JSON format
  content = jsonencode({
    Version = "2012-10-17" # IAM policy language version (required)
    Statement = [
      # STATEMENT 1: Block EC2 instance launches using non-approved AMIs
      {
        Sid    = "DenyEC2LaunchWithNonApprovedAMIs" # Statement identifier for troubleshooting
        Effect = "Deny"                             # Explicitly deny the actions
        Action = [                                  # All EC2 launch methods
          "ec2:RunInstances",          # Standard instance launch
          "ec2:CreateFleet",           # EC2 Fleet launch
          "ec2:RequestSpotInstances", # Spot instance request
          "ec2:RunScheduledInstances" # Scheduled reserved instances
        ]
        Resource = "arn:aws:ec2:*::image/*" # Apply to all AMI resources in all regions
        Condition = {                       # Conditional enforcement
          StringNotEquals = {               # Deny if condition is NOT met
            "ec2:Owner" = local.sorted_allowlist # AMI owner must be in allowlist
          }
        }
      },
      # STATEMENT 2: Block AMI creation/import in workload accounts
      # Prevents "side-loading" or creating custom AMIs outside the pipeline
      {
        Sid    = "DenyAMICreationAndSideload" # Statement ID
        Effect = "Deny"                       # Deny these actions
        Action = [                            # All AMI creation methods
          "ec2:CreateImage",   # Create AMI from running instance
          "ec2:CopyImage",     # Copy AMI from another region/account
          "ec2:RegisterImage", # Register external AMI
          "ec2:ImportImage"    # Import VM image as AMI
        ]
        Resource = "*" # Apply to all resources (no specific resource filtering)
      },
      # STATEMENT 3: Block making AMIs publicly accessible
      # Prevents data exfiltration via public AMI sharing
      {
        Sid    = "DenyPublicAMISharing" # Statement ID
        Effect = "Deny"                 # Deny this action
        Action = [                      # AMI attribute modification
          "ec2:ModifyImageAttribute" # Changes AMI launch permissions
        ]
        Resource = "arn:aws:ec2:*::image/*"         # Apply to all AMIs
        Condition = {                               # Only deny when making public
          StringEquals = {                          # Exact match condition
            "ec2:Add/group" = "all" # "all" means public (everyone can launch)
          }
        }
      }
    ]
  })

  # Merge tags for the SCP
  tags = merge(
    var.tags,                                 # Base tags from variables
    {
      Name        = var.scp_policy_name       # SCP-specific name tag
      PolicyType  = "SERVICE_CONTROL_POLICY"  # Tag indicating this is an SCP
      Environment = var.environment           # Environment tag (dev/prd)
    }
  )
}

# ==========================================================================
# POLICY ATTACHMENTS - SCP
# ==========================================================================
# Attach the SCP to specified target IDs for enforcement
# for_each creates one attachment per target ID

resource "aws_organizations_policy_attachment" "scp" {
  for_each = toset(var.target_ids) # Convert list to set for for_each iteration

  policy_id = aws_organizations_policy.scp.id # Reference to SCP created above
  target_id = each.value                       # OU/Root/Account ID from target_ids list
}

# ==========================================================================
# VALIDATION - EXPIRED EXCEPTIONS CHECK
# ==========================================================================
# Fail the Terraform apply if any expired exceptions are found
# This forces cleanup of expired exceptions before deployment proceeds
# Uses null_resource with local-exec to run shell validation

resource "null_resource" "check_expired_exceptions" {
  # Triggers determine when this resource should re-run
  # Re-runs whenever expired exceptions count or list changes
  triggers = {
    expired_count = length(local.expired_exceptions)        # Number of expired exceptions
    expired_list  = jsonencode(local.expired_exceptions)    # JSON list for change detection
  }

  # local-exec provisioner runs shell command on the machine running Terraform
  provisioner "local-exec" {
    # Heredoc syntax for multi-line bash script
    command = <<-EOT
      # Check if any expired exceptions exist
      if [ ${length(local.expired_exceptions)} -gt 0 ]; then
        # Print warning message to console
        echo "⚠️  WARNING: Found ${length(local.expired_exceptions)} EXPIRED exceptions:"
        # Use jq to parse JSON and format each expired exception
        echo '${jsonencode(local.expired_exceptions)}' | jq -r 'to_entries[] | "  • Account: \(.key) expired on \(.value)"'
        echo "" # Empty line
        # Instruct user to remove expired exceptions
        echo "Please remove expired exceptions from terraform.tfvars"
        # Exit with error code 1 to fail the Terraform apply
        exit 1
      fi
    EOT
    interpreter = ["bash", "-c"] # Use bash to execute the command
  }
}
