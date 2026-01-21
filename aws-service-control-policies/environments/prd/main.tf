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

  policy_name  = "Deny Policy"
  file_date    = "2025-03-26"
  description  = "Catch-all deny policy for suspended accounts"

  target_ids = [var.suspended]
}

module "global-policies-prd" {
  source = "../../modules/organizations"

  policy_name  = "Global_Policies"
  file_date    = "2025-11-19"
  description  = "Policies in place for all accounts"

  target_ids = [var.root]
}

module "imds-v2-policy" {
  source = "../../modules/organizations"

  policy_name = "IMDSv2_Policy"
  file_date   = "2025-03-26"

  target_ids = [var.audit, var.workloads, var.sandbox]
}

# ============================================================================
# AMI GOVERNANCE POLICIES - Prasa Operations
# ============================================================================
# Approved AMI Publishers:
#   - 565656565656 (prasains-operations-dev-use2)
#   - 666363636363 (prasains-operations-prd-use2)
# ============================================================================

# AMI Guardrail SCP - Prevents non-approved AMI usage, sideloading, public sharing
# Only AMIs from Prasa Operations accounts are permitted
module "scp-ami-guardrail" {
  source = "../../modules/organizations"

  policy_name = "scp-ami-guardrail"
  file_date   = "2026-01-18"
  description = "SCP to enforce Prasa AMI governance: only prasa-* AMIs from Operations accounts (565656565656, 666363636363), prevent sideloading, deny public sharing"
  type        = "SERVICE_CONTROL_POLICY"

  # Deploy to workloads and sandbox OUs
  target_ids = [var.workloads, var.sandbox]

  # Exception expiry feature (disabled by default)
  enable_exception_expiry = false
  exception_accounts      = {}
}

# EC2 Declarative Policy - Enforces AMI settings at the EC2 service level
# Prasa Operations accounts only: prasains-operations-dev-use2, prasains-operations-prd-use2
module "declarative-policy-ec2" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2"
  file_date   = "2026-01-18"
  description = "EC2 Declarative Policy for Prasa AMI governance: only prasa-* AMIs from Operations accounts permitted"
  type        = "DECLARATIVE_POLICY_EC2"

  # Deploy to workloads and sandbox OUs
  target_ids = [var.workloads, var.sandbox]

  # Exception expiry feature (disabled by default)
  enable_exception_expiry = false
  exception_accounts      = {}
}
