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
# AMI GOVERNANCE POLICIES
# ============================================================================

# AMI Guardrail SCP - Prevents non-approved AMI usage, sideloading, public sharing
# Principal-based restrictions: Exception AMIs only usable by Admin/Developer roles
module "scp-ami-guardrail" {
  source = "../../modules/organizations"

  policy_name = "scp-ami-guardrail"
  file_date   = "2026-01-11"
  description = "SCP to enforce AMI governance: block non-approved AMIs, principal-based exception restrictions, prevent sideloading, deny public sharing"
  type        = "SERVICE_CONTROL_POLICY"

  # Deploy to workloads and sandbox OUs
  target_ids = [var.workloads, var.sandbox]

  # Exception expiry feature (disabled by default)
  enable_exception_expiry = false
  exception_accounts      = {}
}

# EC2 Declarative Policy - Enforces AMI settings at the EC2 service level
module "declarative-policy-ec2" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2"
  file_date   = "2026-01-06"
  description = "EC2 Declarative Policy for AMI governance: allowed images and block public access"
  type        = "DECLARATIVE_POLICY_EC2"

  # Deploy to workloads and sandbox OUs
  target_ids = [var.workloads, var.sandbox]

  # Exception expiry feature (disabled by default)
  enable_exception_expiry = false
  exception_accounts      = {}
}
