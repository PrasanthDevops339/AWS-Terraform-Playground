
#############################################
# Service Control Policies (SCPs) Deployment
#############################################

# Local variables for policy files
locals {
  scp_policies = {
    ebs_governance = {
      name        = "EBS-Governance-Policy"
      description = "Enforces EBS encryption, tagging, and volume type restrictions"
      policy_file = "${path.module}/../../../aws-service-control-policies/policies/ebs-governance.json"
      enabled     = var.enable_ebs_scp
    }
    sqs_governance = {
      name        = "SQS-Governance-Policy"
      description = "Enforces SQS encryption, tagging, and access controls"
      policy_file = "${path.module}/../../../aws-service-control-policies/policies/sqs-governance.json"
      enabled     = var.enable_sqs_scp
    }
    efs_governance = {
      name        = "EFS-Governance-Policy"
      description = "Enforces EFS encryption, backup policies, and lifecycle management"
      policy_file = "${path.module}/../../../aws-service-control-policies/policies/efs-governance.json"
      enabled     = var.enable_efs_scp
    }
  }

  # Filter enabled policies
  enabled_policies = {
    for key, policy in local.scp_policies : key => policy
    if policy.enabled
  }
}

# Create AWS Organizations Policies
resource "aws_organizations_policy" "service_control_policies" {
  for_each = local.enabled_policies

  name        = "${local.name_prefix}-${each.value.name}"
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  content     = file(each.value.policy_file)

  tags = merge(
    {
      "Name"       = "${local.name_prefix}-${each.value.name}"
      "PolicyType" = "SCP"
      "Service"    = upper(each.key)
    },
    var.tags
  )
}

# Attach policies to organizational unit or account
resource "aws_organizations_policy_attachment" "scp_attachments" {
  for_each = var.scp_attach_to_target ? local.enabled_policies : {}

  policy_id = aws_organizations_policy.service_control_policies[each.key].id