module "aft-resource-protection" {
  source = "../../modules/organizations"

  policy_name = "aft-resource-protection"
  file_date   = "2025-06-23"
  description = "SCP to protect resources that AFT deploys to vended accounts"

  target_ids = [var.acme_cloudaws_afttest2]
}

module "baseline-scps-workloads-dev" {
  source = "../../modules/organizations"

  policy_name = "Baseline SCPs workloads"
  file_date   = "2025-03-10"

  target_ids = [var.workloads]
}

module "aft-SecurityServices-protection" {
  source = "../../modules/organizations"

  policy_name = "Deny Tampering With Security Services ExceptAFT"
  file_date   = "2025-06-26"
  description = "This is to Deny users from tampering the Cloudtrail,guardduty,inspector,cloudtrail other the"

  target_ids = [var.acme_cloudaws_afttest2]
}

module "acme-master-dev-sandbox-account-scps01" {
  source = "../../modules/organizations"

  policy_name = "acme-master-dev-sandbox-account-scps01"
  file_date   = "2025-03-10"
  description = "Account Level Sandbox SCP"

  target_ids = [var.acme_playground_dev]
}

module "global-policies-dev" {
  source = "../../modules/organizations"

  policy_name = "Global_Policies"
  file_date   = "2025-07-22"
  description = "Policies applied to every account"

  target_ids = [var.root]
}

module "sandbox-ou-scp-1" {
  source = "../../modules/organizations"

  policy_name = "Sandbox OU SCP 1"
  file_date   = "2025-03-10"

  target_ids = [var.sandbox]
}

module "sandbox-ou-scp-2" {
  source = "../../modules/organizations"

  policy_name = "Sandbox OU SCP 2"
  file_date   = "2025-03-10"

  target_ids = [var.sandbox]
}

module "sandbox-ou-scp-3" {
  source = "../../modules/organizations"

  policy_name = "Sandbox OU SCP 3"
  file_date   = "2025-03-10"

  target_ids = [var.sandbox]
}

module "security-ou-sandbox-perimeter-policy" {
  source = "../../modules/organizations"

  policy_name = "security-ou-sandbox-perimeter-policy"
  file_date   = "2025-03-10"

  target_ids = [var.security]
}

module "testing-launch-wizard" {
  source = "../../modules/organizations"

  policy_name = "Testing Launch Wizard"
  file_date   = "2025-03-10"
  description = "Testing policy to stop default launch wizards from enabling 0.0.0.0/0"

  target_ids = [var.acme_playground_dev]
}

module "dev-sandbox-rcp-scp-test" {
  source = "../../modules/organizations"

  policy_name = "dev-sandbox-rcp-scp-test"
  file_date   = "2025-06-03"
  description = "adding SCP to sandbox to test blocking cross account s3 access"

  target_ids = [var.acme_playground_dev]
}

module "dev-workload-rcp-scp-test" {
  source = "../../modules/organizations"

  policy_name = "dev-workload-rcp-scp-test"
  file_date   = "2025-06-03"
  description = "adding SCP to workload to test blocking cross account s3 access"

  target_ids = [var.workloads]
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
# Hardcoded accounts: 565656565656 (prasains-operations-dev-use2), 666363636363 (prasains-operations-prd-use2)
module "scp-ami-guardrail" {
  source = "../../modules/organizations"

  policy_name = "scp-ami-guardrail"
  file_date   = "2026-01-18"
  description = "SCP to enforce Prasa AMI governance: only prasa-* AMIs from Operations accounts (565656565656, 666363636363), prevent sideloading, deny public sharing"
  type        = "SERVICE_CONTROL_POLICY"

  # Deploy to workloads OU - adjust target as needed
  target_ids = [var.workloads]
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

  # Deploy to workloads OU - adjust target as needed
  target_ids = [var.workloads]

  # Policy template variables - only enforcement_mode is configurable
  policy_vars = {
    # Enforcement mode: "audit_mode" (logs violations without blocking) or "enabled" (actively blocks)
    # Starting with audit_mode for dev environment to assess impact before full enforcement
    enforcement_mode = "audit_mode"
  }
}
