module "aft-resource-protection" {
  source = "../../modules/organizations"

  policy_name = "aft-resource-protection"
  file_date   = "2025-06-23"
  description = "SCP to protect resources that AFT deploys to vended accounts"

  # AFT management (account-level)
  target_ids = [var.acme_aftwld_dev]
}

module "baseline-scps-legacy-workloads" {
  source = "../../modules/organizations"

  policy_name = "Baseline SCPs Legacy Workloads"
  file_date   = "2025-03-26"
  description = "Baseline guardrails for legacy workloads"

  target_ids = [var.workloadsLEGACY]

  tags = {
    "Owner" = "CloudSec_DL@example.com"
  }
}

module "baseline-scps-workloads-prd" {
  source = "../../modules/organizations"

  policy_name = "Baseline SCPs Workloads"
  file_date   = "2025-03-26"
  description = "Baseline guardrails for workloads"

  target_ids = [var.workloads, var.sandbox]
}

module "deny-policy" {
  source = "../../modules/organizations"

  policy_name = "Deny Policy"
  file_date   = "2025-03-26"
  description = "Catch-all deny policy for suspended accounts"

  target_ids = [var.suspended]
}

module "global-policies-prd" {
  source = "../../modules/organizations"

  policy_name = "Global_Policies"
  file_date   = "2025-11-19"
  description = "Policies in place for all accounts"

  target_ids = [var.root]
}

module "imds-v2-policy" {
  source = "../../modules/organizations"

  policy_name = "IMDSv2_Policy"
  file_date   = "2025-03-26"

  target_ids = [var.audit, var.workloads, var.sandbox]
}

# ============================================================================
# AMI GOVERNANCE - Single combined SCP + per-app Declarative Policies
# ============================================================================
# Ops AMI Publishers (golden + app-specific pras-* AMIs):
#   - 565656565656 (prasains-operations-dev-use2)
#   - 666363636363 (prasains-operations-prd-use2)
#
# Exception accounts are exempted from the baseline guardrail so that their
# app-specific exception AMIs are only blocked by the targeted per-app
# restriction statements within the same SCP.
# ============================================================================

# Single combined AMI governance SCP.
# Replaces: scp-ami-guardrail (2026-01-18) + scp-ami-account-restrictions (2026-03-18).
# Contains 5 statements -- see policies/scp-ami-governance-design.md for full details.
module "scp-ami-governance" {
  source = "../../modules/organizations"

  policy_name = "scp-ami-governance"
  file_date   = "2026-03-18"
  description = "Combined AMI governance SCP: org-wide guardrail + exception AMI account restrictions for Datalake, Transit, AgcyDshBrd, TermCond, DataSync, ClaimsData"
  type        = "SERVICE_CONTROL_POLICY"

  # Attached at root so it covers every account in the org
  target_ids = [var.root]
}

# EC2 Declarative Policy - Enforces AMI settings at the EC2 service level
# Prasa Operations accounts only: prasains-operations-dev-use2, prasains-operations-prd-use2
# Hardcoded AMI controls: 300-day max age, 0-day deprecation tolerance
module "declarative-policy-ec2" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2"
  file_date   = "2026-01-18"
  description = "EC2 Declarative Policy for Prasa AMI governance: only prasa-* AMIs from Operations accounts permitted"
  type        = "DECLARATIVE_POLICY_EC2"

  # Deploy to workloads and sandbox OUs
  target_ids = [var.workloads, var.sandbox]

  # Policy template variables - only enforcement_mode is configurable
  policy_vars = {
    # Enforcement mode: "audit_mode" (logs violations without blocking) or "enabled" (actively blocks)
    # Starting with audit_mode for initial rollout to assess impact before full enforcement
    enforcement_mode = "audit_mode"
  }
}

# ============================================================================
# PER-APP EC2 DECLARATIVE POLICIES (Amazon-owned service AMIs)
# ============================================================================
# Amazon-owned service AMIs (eks, datasync, storage-gateway, emr) all share
# ec2:Owner="amazon" so they cannot be distinguished in an SCP condition.
# These declarative policies enforce the restriction at the EC2 service level
# by allowing only the relevant image_names for each application OU.
#
# PREREQUISITE: The org-wide declarative-policy-ec2 must set
#   image_criteria @@operators_allowed_for_child_policies = ["@@append"]
#   so these per-OU policies add their criteria on top of the baseline.
# ============================================================================

module "declarative-policy-ec2-datalake" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2-datalake"
  file_date   = "2026-03-18"
  description = "EC2 Declarative Policy for Datalake OU: allows amazon-eks-node-al2023-x86_64-standard-* and UpsolverPrivateVpc-* exception AMIs"
  type        = "DECLARATIVE_POLICY_EC2"

  target_ids = [var.pras_datalake_ou]

  policy_vars = {
    enforcement_mode = "enabled"
  }
}

module "declarative-policy-ec2-transit" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2-transit"
  file_date   = "2026-03-18"
  description = "EC2 Declarative Policy for Transit OU: allows Gigamon and Cisco ftdv marketplace AMIs"
  type        = "DECLARATIVE_POLICY_EC2"

  target_ids = [var.pras_transit_ou]

  policy_vars = {
    enforcement_mode = "enabled"
  }
}

module "declarative-policy-ec2-agcydshbrd" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2-agcydshbrd"
  file_date   = "2026-03-18"
  description = "EC2 Declarative Policy for AgcyDshBrd OU: allows aws-datasync-* exception AMIs"
  type        = "DECLARATIVE_POLICY_EC2"

  target_ids = [var.pras_agcydshbrd_ou]

  policy_vars = {
    enforcement_mode = "enabled"
  }
}

module "declarative-policy-ec2-termcond" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2-termcond"
  file_date   = "2026-03-18"
  description = "EC2 Declarative Policy for TermCond OU: allows aws-storage-gateway-FILE_S3-* exception AMIs"
  type        = "DECLARATIVE_POLICY_EC2"

  target_ids = [var.pras_termcond_ou]

  policy_vars = {
    enforcement_mode = "enabled"
  }
}

module "declarative-policy-ec2-datasync" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2-datasync"
  file_date   = "2026-03-18"
  description = "EC2 Declarative Policy for DataSync OU: allows aws-datasync-* exception AMIs"
  type        = "DECLARATIVE_POLICY_EC2"

  target_ids = [var.pras_datasync_ou]

  policy_vars = {
    enforcement_mode = "enabled"
  }
}

module "declarative-policy-ec2-claimsdata" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2-claimsdata"
  file_date   = "2026-03-18"
  description = "EC2 Declarative Policy for ClaimsData OU: allows emr-* exception AMIs"
  type        = "DECLARATIVE_POLICY_EC2"

  target_ids = [var.pras_claimsdata_ou]

  policy_vars = {
    enforcement_mode = "enabled"
  }
}


