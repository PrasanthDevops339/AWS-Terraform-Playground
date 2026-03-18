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

# ============================================================================
# EXCEPTION AMI ACCOUNT RESTRICTIONS
# ============================================================================
# Each application has 3 accounts (dev, tst, prd). Exception AMIs may only
# run in their owning application's accounts.
#
# Golden AMIs (pras-al2023-*, pras-al2-*, pras-rhel8-*, pras-rhel9-*,
# pras-win22-*) are org-wide approved and NOT restricted here.
#
# Application-Specific AMIs from image 1 (pras-mlal2-*, pras-opsdir-mlal2-*)
# are published from the ops accounts. AWS SCPs cannot filter by AMI name,
# so those must be handled via per-OU declarative policies (not implemented
# in this PR -- SCP approach is not viable for same-owner AMIs).
#
# Two enforcement mechanisms are used:
#   1. SCP (scp-ami-account-restrictions): restricts third-party owner AMIs
#      (Upsolver: ec2:Owner) and marketplace AMIs (ec2:ProductCode).
#   2. Declarative Policy per app OU: restricts Amazon-owned service AMIs
#      (eks, datasync, storage-gateway, emr) which share ec2:Owner="amazon"
#      and therefore cannot be distinguished in an SCP.
# ============================================================================

# SCP: Restricts Upsolver AMIs to Datalake accounts only.
# Restricts marketplace (Gigamon + Cisco ftdv) AMIs to Transit accounts only.
# Attached at root OU so it applies to every account in the org.
module "scp-ami-account-restrictions" {
  source = "../../modules/organizations"

  policy_name = "scp-ami-account-restrictions"
  file_date   = "2026-03-18"
  description = "SCP to restrict exception AMIs (Upsolver, Gigamon, Cisco ftdv) to their owning application accounts only"
  type        = "SERVICE_CONTROL_POLICY"

  target_ids = [var.root]
}

# Per-app declarative policies for Amazon-owned exception AMIs.
# Each policy is attached to the application's OU. It allows the app-specific
# AMIs in addition to whatever the parent (org-wide) declarative policy allows.
# NOTE: The org-wide declarative-policy-ec2 must have image_criteria
#       @@operators_allowed_for_child_policies set to ["@@append"] (not ["@@none"])
#       for these per-OU policies to take additive effect.

module "declarative-policy-ec2-datalake" {
  source = "../../modules/organizations"

  policy_name = "declarative-policy-ec2-datalake"
  file_date   = "2026-03-18"
  description = "EC2 Declarative Policy for Datalake OU: allows amazon-eks-node-al2023-x86_64-standard-* and UpsolverPrivateVpc-* exception AMIs"
  type        = "DECLARATIVE_POLICY_EC2"

  target_ids = [var.pras_datalake_ou]

  policy_vars = {
    enforcement_mode = "audit_mode"
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
    enforcement_mode = "audit_mode"
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
    enforcement_mode = "audit_mode"
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
    enforcement_mode = "audit_mode"
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
    enforcement_mode = "audit_mode"
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
    enforcement_mode = "audit_mode"
  }
}

