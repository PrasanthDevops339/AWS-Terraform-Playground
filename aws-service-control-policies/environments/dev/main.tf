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

  policy_name  = "Deny Tampering With Security Services ExceptAFT"
  file_date    = "2025-06-26"
  description  = "This is to Deny users from tampering the Cloudtrail,guardduty,inspector,cloudtrail other the"

  target_ids = [var.acme_cloudaws_afttest2]
}

module "acme-master-dev-sandbox-account-scps01" {
  source = "../../modules/organizations"

  policy_name  = "acme-master-dev-sandbox-account-scps01"
  file_date    = "2025-03-10"
  description  = "Account Level Sandbox SCP"

  target_ids = [var.acme_playground_dev]
}

module "global-policies-dev" {
  source = "../../modules/organizations"

  policy_name  = "Global_Policies"
  file_date    = "2025-07-22"
  description  = "Policies applied to every account"

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

  policy_name  = "Testing Launch Wizard"
  file_date    = "2025-03-10"
  description  = "Testing policy to stop default launch wizards from enabling 0.0.0.0/0"

  target_ids = [var.acme_playground_dev]
}

module "dev-sandbox-rcp-scp-test" {
  source = "../../modules/organizations"

  policy_name  = "dev-sandbox-rcp-scp-test"
  file_date    = "2025-06-03"
  description  = "adding SCP to sandbox to test blocking cross account s3 access"

  target_ids = [var.acme_playground_dev]
}

module "dev-workload-rcp-scp-test" {
  source = "../../modules/organizations"

  policy_name  = "dev-workload-rcp-scp-test"
  file_date    = "2025-06-03"
  description  = "adding SCP to workload to test blocking cross account s3 access"

  target_ids = [var.workloads]
}

# ============================================================================
# AMI GOVERNANCE POLICIES
# ============================================================================

# AMI Guardrail SCP - Prevents non-approved AMI usage, sideloading, public sharing
module "scp-ami-guardrail" {
  source = "../../modules/organizations"

  policy_name = "scp-ami-guardrail"
  file_date   = "2026-01-06"
  description = "SCP to enforce AMI governance: block non-approved AMIs, prevent sideloading, deny public sharing"
  type        = "SERVICE_CONTROL_POLICY"

  # Deploy to workloads OU - adjust target as needed
  target_ids = [var.workloads]

  # Exception expiry feature (disabled by default)
  # When enabled, accounts in exception_accounts map will be automatically
  # removed from exceptions after their expiry date
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

  # Deploy to workloads OU - adjust target as needed
  target_ids = [var.workloads]

  # Exception expiry feature (disabled by default)
  enable_exception_expiry = false
  exception_accounts      = {}
}
