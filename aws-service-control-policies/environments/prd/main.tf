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
