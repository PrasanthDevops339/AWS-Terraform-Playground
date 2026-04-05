# Operations Runbook: AWS Encryption Compliance Controls

EBS · SQS · EFS | AWS Config + OPA Policy Governance

---

| Field | Value |
| --- | --- |
| **Document Type** | Operations Runbook |
| **Audience** | Cloud Platform Engineers, DevOps / SRE, Security Engineers |
| **Last Updated** | 2026-04-05 |
| **Status** | Active |
| **Program Runbook** | [RUNBOOK-PROGRAM-LEVEL.md](./RUNBOOK-PROGRAM-LEVEL.md) |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Repositories and File Map](#2-repositories-and-file-map)
3. [AWS Config Rules Reference](#3-aws-config-rules-reference)
4. [OPA Policy Reference](#4-opa-policy-reference)
5. [Deployment — Org Config Rules (custom-config-rules)](#5-deployment--org-config-rules)
6. [Deployment — AFT Lambda Rules](#6-deployment--aft-lambda-rules)
7. [Deployment — OPA Policies](#7-deployment--opa-policies)
8. [Adding a New Guard Rule](#8-adding-a-new-guard-rule)
9. [Updating an Existing Guard Rule](#9-updating-an-existing-guard-rule)
10. [Checking Compliance Status](#10-checking-compliance-status)
11. [Troubleshooting](#11-troubleshooting)
12. [Excluded Accounts](#12-excluded-accounts)
13. [Variable Reference](#13-variable-reference)
14. [CCOPS — Cloud Ops Governance Platform](#14-ccops--cloud-ops-governance-platform)

---

## 1. Overview

Two repositories manage encryption compliance controls. A third repository handles shift-left enforcement at Terraform plan time.

| Repo | Controls | Deployment Trigger |
| --- | --- | --- |
| `custom-config-rules` | EBS, SQS, EFS — Guard rules as Org Conformance Packs | Manual `terraform apply` from management account |
| `terraform-aft-account-customizations` | EFS TLS enforcement — Lambda-based per-account Config rule | AFT pipeline (account vending / updates) |
| `Terrafrom-OPA-Prasanth` | EBS, EFS — OPA advisory + mandatory shift-left policies | GitLab CI on `terraform plan` |

---

## 2. Repositories and File Map

### 2.1 custom-config-rules

```text
custom-config-rules/
├── environments/
│   ├── prd/
│   │   ├── main.tf                  # Individual policy_rule module calls (port-443)
│   │   ├── cpack_encryption.tf      # Conformance pack for EBS + SQS + EFS (USE2 + USE1)
│   │   ├── lambda_efs_tls.tf        # EFS TLS Lambda deployment (USE2 + USE1)
│   │   ├── data.tf                  # Data sources (account alias, identity)
│   │   └── variables.tf             # excluded_accounts, org IDs
│   └── dev/
│       ├── main.tf                  # EBS rules for dev (account-level, not org)
│       ├── cpack_encryption.tf      # Conformance pack for dev
│       └── ...
├── modules/
│   ├── conformance_pack/
│   │   ├── cpack_template.tf        # Builds YAML from guard/lambda/managed lists
│   │   ├── cpack_organization.tf    # aws_config_organization_conformance_pack resource
│   │   ├── cpack_account.tf         # aws_config_conformance_pack resource (account-level)
│   │   ├── variables.tf             # policy_rules_list, lambda_rules_list, managed_rules_list
│   │   └── templates/
│   │       ├── guard_template.yml   # YAML block template for Guard rules
│   │       ├── lambda_template.yml  # YAML block template for Lambda rules
│   │       └── managed_template.yml # YAML block template for AWS Managed rules
│   └── policy_rule/
│       ├── rule_organization.tf     # aws_config_organization_custom_policy_rule
│       ├── rule_account.tf          # aws_config_custom_policy_rule (account-level)
│       └── variables.tf
└── policies/
    ├── ebs-is-encrypted/
    │   ├── ebs-is-encrypted-2025-10-30.guard   # Previous version
    │   └── ebs-is-encrypted-2026-01-09.guard   # Current version (active)
    ├── sqs-is-encrypted/
    │   ├── sqs-is-encrypted-2025-10-30.guard   # Current version (active)
    │   └── sqs-is-encrypted-2026-01-27.guard   # Newer version (staging)
    └── efs-is-encrypted/
        └── efs-is-encrypted-2025-10-30.guard   # Current version (active)
```

### 2.2 terraform-aft-account-customizations

```text
terraform-aft-account-customizations/
├── exceptions/
│   └── terraform/
│       ├── conformance-pack-templates.tf   # Lambda conformance pack YAML template
│       ├── lambda-rules-enforcement.tf     # EFS TLS Lambda + conformance pack deployment
│       ├── locals.tf                       # name_prefix
│       ├── variables.tf                    # region, account_name, kms_key_arn, SCP toggles
│       └── data.tf                         # aws_caller_identity, aws_region
└── modules/
    ├── lambda/
    │   ├── main.tf                         # aws_lambda_function resource
    │   ├── main-iam.tf                     # Lambda execution role + policy
    │   ├── main-s3.tf                      # S3 bucket for Lambda package
    │   ├── main-cloudwatch.tf              # CloudWatch log group
    │   └── variables.tf
    ├── scripts/
    │   └── efs-tls-enforcement/
    │       └── efs_tls_enforcement.py      # Lambda handler — EFS TLS validation
    └── policy-files/
        └── efs_tls_compliance.json         # IAM policy for Lambda (DescribeFileSystemPolicy)
```

### 2.3 Terrafrom-OPA-Prasanth

```text
Terrafrom-OPA-Prasanth/
├── global-advisory-policies/
│   ├── policies.hcl                         # Advisory policy registry (enforcement_level = advisory)
│   ├── aws_ebs_001_advise_encryption.rego   # EBS encryption advisory
│   ├── aws_efs_001_advise_encryption.rego   # EFS encryption advisory
│   ├── aws_efs_001_advise_module_usage.rego # EFS module usage advisory (placeholder)
│   └── utils/
│       └── advise_module_usage.rego         # Shared utility for module usage checks
└── global-manadatery-policies/
    ├── policies.hcl                          # Mandatory policy registry (enforcement_level = mandatory)
    └── aws_efs_001_mandatory_encryption.rego # EFS KMS encryption — BLOCKS plan
```

---

## 3. AWS Config Rules Reference

### 3.1 EBS — Guard Rule

File: [custom-config-rules/policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard](custom-config-rules/policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard)

```text
rule ebsIsEncrypted when resourceType == "AWS::EC2::Volume" {
    configuration.encrypted == true <<EBS Volumes must be encrypted>>
}
```

| Field | Value |
| --- | --- |
| Resource Types | `AWS::EC2::Volume`, `AWS::EC2::Snapshot` |
| Active Version | `2026-01-09` |
| Deployed In | `environments/prd/cpack_encryption.tf` — `cpack_encryption` (USE2) and `cpack_encryption_use1` (USE1) |
| Conformance Pack Name | `<account-alias>-encryption-validation` |
| Finding | `NON_COMPLIANT` when `configuration.encrypted != true` |

---

### 3.2 SQS — Guard Rule

File: [custom-config-rules/policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard](custom-config-rules/policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard)

```text
rule sqsIsEncrypted when resourceType == "AWS::SQS::Queue" {
    configuration.sqsManagedSseEnabled == true <<SQS must be encrypted at the time of creation>>
    OR
    configuration.kmsMasterKeyId != null
}
```

| Field | Value |
| --- | --- |
| Resource Types | `AWS::SQS::Queue` |
| Active Version | `2025-10-30` |
| Deployed In | `environments/prd/cpack_encryption.tf` — `cpack_encryption` (USE2) and `cpack_encryption_use1` (USE1) |
| Conformance Pack Name | `<account-alias>-encryption-validation` |
| Finding | `NON_COMPLIANT` when queue has no SSE-SQS and no KMS key |

> **Note:** A newer version `sqs-is-encrypted-2026-01-27.guard` exists in the policies directory. It is not yet active. Update `config_rule_version` in `cpack_encryption.tf` to activate it.

---

### 3.3 EFS — Guard Rule (at-rest)

File: [custom-config-rules/policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard](custom-config-rules/policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard)

```text
rule efsIsEncrypted when resourceType == "AWS::EFS::FileSystem" {
    configuration.Encrypted == true <<EFS's must be encrypted>>
}
```

| Field | Value |
| --- | --- |
| Resource Types | `AWS::EFS::FileSystem` |
| Active Version | `2025-10-30` |
| Deployed In | `environments/prd/cpack_encryption.tf` — `cpack_encryption` module |
| Conformance Pack Name | `<account-alias>-encryption-validation` |
| Finding | `NON_COMPLIANT` when `configuration.Encrypted != true` |

---

### 3.4 EFS — Lambda Rule (TLS in-transit) — Deployed via AFT

Script: [terraform-aft-account-customizations/modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py](terraform-aft-account-customizations/modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py)

Why Lambda (not Guard): EFS resource policies are **not included** in AWS Config configuration items. The Lambda calls `elasticfilesystem:DescribeFileSystemPolicy` to retrieve the policy, then validates that a `Deny` statement with `aws:SecureTransport = false` exists.

| Field | Value |
| --- | --- |
| Resource Types | `AWS::EFS::FileSystem` |
| Trigger | `ConfigurationItemChangeNotification` |
| Runtime | Python 3.12, timeout 900s |
| Deployed Via | AFT pipeline per account |
| Conformance Pack Name | `Lambdarulesconformancepack` |
| Config Rule Name | `efstlsenforcement_<account_id>` |
| Finding | `NON_COMPLIANT` when EFS policy does not deny non-TLS access |

---

## 4. OPA Policy Reference

OPA policies are evaluated against the `terraform plan -out plan.tfplan && terraform show -json plan.tfplan` output in GitLab CI.

### 4.1 Advisory Policies (never block)

Registry: [Terrafrom-OPA-Prasanth/global-advisory-policies/policies.hcl](Terrafrom-OPA-Prasanth/global-advisory-policies/policies.hcl)

#### EBS Advisory — `aws_ebs_001_advise_encryption.rego`

| Code | Resource | Condition | Message |
| --- | --- | --- | --- |
| `EBS-ENC-001` | `aws_ebs_volume` | `encrypted != true` | Advisory: standalone EBS volume not encrypted |
| `EBS-ENC-002` | `aws_instance` | `root_block_device.encrypted != true` | Advisory: EC2 root volume not encrypted |
| `EBS-ENC-003` | `aws_instance` | `ebs_block_device.encrypted != true` | Advisory: EC2 attached EBS volume not encrypted |

- **Package:** `terraform.policies.aws_ebs_001_advise_encryption`
- **Policy version:** `2.0.0` (HEAD) / `2.2.0` (feature branch — pending merge)
- **`authz`:** Always `true` — never blocks the plan

#### EFS Advisory — `aws_efs_001_advise_encryption.rego`

| Code | Resource | Condition | Message |
| --- | --- | --- | --- |
| `EFS-ENC-001` | `aws_efs_file_system` | `encrypted != true` | Advisory: EFS not encrypted |
| `EFS-ENC-002` | `aws_efs_file_system` | `encrypted = true` but no `kms_key_id` | Advisory: EFS encrypted but no CMK |
| `EFS-ENC-003` | `aws_efs_file_system` | `kms_key_id` not starting with `arn:aws:kms:` | Advisory: invalid KMS ARN format |
| `EFS-ENC-004` | `aws_efs_replication_configuration` | destination has no `kms_key_id` | Advisory: replication destination missing CMK |

- **Package:** `terraform.policies.aws_efs_001_advise_encryption`
- **Policy version:** `1.0.0`

#### Module Usage Advisories

The `policies.hcl` also includes advisory policies for module usage across many services (EFS, SQS, EBS, etc.) — these warn if Terraform resources are created directly instead of through approved service modules.

> **EFS module usage note:** `aws_efs_001_advise_module_usage.rego` is currently a placeholder (contains only a package declaration). Full implementation is pending.

---

### 4.2 Mandatory Policies (block on violation)

Registry: [Terrafrom-OPA-Prasanth/global-manadatery-policies/policies.hcl](Terrafrom-OPA-Prasanth/global-manadatery-policies/policies.hcl)

#### EFS Mandatory — `aws_efs_001_mandatory_encryption.rego`

| Code | Resource | Condition | Action |
| --- | --- | --- | --- |
| `EFS-ENC-001` | `aws_efs_file_system` | `encrypted != true` | **DENY — blocks plan** |
| `EFS-ENC-002` | `aws_efs_file_system` | No CMK (`kms_key_id` null or empty) | **DENY — blocks plan** |
| `EFS-ENC-003` | `aws_efs_file_system` | `kms_key_id` not a valid KMS ARN | **DENY — blocks plan** |
| `EFS-ENC-004` | `aws_efs_replication_configuration` | Destination missing CMK | **DENY — blocks plan** |

- **Package:** `terraform.policies.aws_efs_001_mandatory_encryption`
- **Severity:** HIGH
- **Frameworks:** CIS AWS 2.4.1, AWS Well-Architected SEC08-BP02
- **`deny` set:** Non-empty set blocks pipeline

---

## 5. Deployment — Org Config Rules

### 5.1 Prerequisites

- Terraform state backend configured (S3 + DynamoDB)
- AWS credentials for the management / delegated admin account
- AWS Config must be enabled in all target accounts and regions
- Excluded account IDs updated in `cpack_encryption.tf`

### 5.2 Deploy to Production

```bash
cd AWS-Terraform-Playground/custom-config-rules/environments/prd

# Review the plan
terraform init
terraform plan

# Apply — deploys org conformance pack to all member accounts
terraform apply
```

The `cpack_template.tf` module reads Guard policy files at apply time and generates a CloudFormation YAML template. The org conformance pack is then pushed to all member accounts (minus excluded ones).

### 5.3 Deploy to Dev (account-level, non-org)

```bash
cd AWS-Terraform-Playground/custom-config-rules/environments/dev

terraform init
terraform plan
terraform apply
```

Dev uses account-level rules (`organization_rule = false` / `organization_pack = false`). The `is_pre_dev` variable controls whether rules are deployed to a pre-dev environment.

### 5.4 Verify Deployment

```bash
# List org conformance packs (run from management account)
aws configservice describe-organization-conformance-packs \
  --query 'OrganizationConformancePacks[*].{Name:OrganizationConformancePackName,Status:DeliveryS3Bucket}'

# Check conformance pack status across accounts
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name "<account-alias>-encryption-validation"
```

---

## 6. Deployment — AFT Lambda Rules

### 6.1 Overview

AFT automatically runs the `exceptions/terraform/` customization during:

- New account vending
- Re-trigger of account customization pipeline

### 6.2 Manual Re-trigger (existing account)

```bash
# Re-trigger AFT customization for a specific account
# (Commands depend on your AFT pipeline — typically via CodePipeline or GitLab)
# <!-- PLACEHOLDER: Insert your AFT pipeline trigger command here -->
```

### 6.3 Verify Lambda Deployment

```bash
# In the target account
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `efs-tls-enforcement`)].{Name:FunctionName,Runtime:Runtime}'

# Check the account-level conformance pack
aws configservice describe-conformance-packs \
  --query 'ConformancePackDetails[?ConformancePackName==`Lambdarulesconformancepack`]'
```

### 6.4 Test Lambda Manually

```bash
# Trigger a Config evaluation for a specific EFS file system
aws configservice start-config-rules-evaluation \
  --config-rule-names "efstlsenforcement_<account_id>"
```

---

## 7. Deployment — OPA Policies

OPA policies are evaluated automatically in GitLab CI on every `terraform plan`. No manual deployment is required.

### 7.1 Policy Execution Flow

```text
GitLab CI Pipeline
└── stage: validate
    ├── terraform init
    ├── terraform plan -out plan.tfplan
    ├── terraform show -json plan.tfplan > plan.json
    └── opa eval \
          --input plan.json \
          --data global-advisory-policies/ \
          --data global-manadatery-policies/ \
          "data.terraform.policies.<policy_name>.deny"
```

### 7.2 Advisory vs Mandatory Behavior

| Policy Type | `policies.hcl` `enforcement_level` | Pipeline Behavior |
| --- | --- | --- |
| Advisory | `"advisory"` | Warnings printed, pipeline continues |
| Mandatory | `"mandatory"` | Non-zero `deny` set = pipeline fails |

### 7.3 Test an OPA Policy Locally

```bash
# Generate plan JSON
terraform plan -out plan.tfplan
terraform show -json plan.tfplan > plan.json

# Test advisory EFS policy
opa eval \
  --input plan.json \
  --data Terrafrom-OPA-Prasanth/global-advisory-policies/ \
  "data.terraform.policies.aws_efs_001_advise_encryption.warn"

# Test mandatory EFS policy
opa eval \
  --input plan.json \
  --data Terrafrom-OPA-Prasanth/global-manadatery-policies/ \
  "data.terraform.policies.aws_efs_001_mandatory_encryption.deny"
```

---

## 8. Adding a New Guard Rule

Follow this procedure when adding a new AWS Config Guard-based rule to the encryption conformance pack.

### Step 1 — Write the Guard Policy

```bash
# Create versioned guard file
touch custom-config-rules/policies/<rule-name>/<rule-name>-$(date +%Y-%m-%d).guard
```

Guard file convention:

```text
rule <ruleName> when resourceType == "<AWS::Service::ResourceType>" {
    configuration.<attribute> == <expected_value> <<Descriptive error message>>
}
```

### Step 2 — Add to the Conformance Pack

Edit [custom-config-rules/environments/prd/cpack_encryption.tf](custom-config-rules/environments/prd/cpack_encryption.tf):

```hcl
module "cpack_encryption" {
  source = "../../modules/conformance_pack"
  # ...existing config...

  policy_rules_list = [
    # ...existing rules...
    {
      config_rule_name     = "<rule-name>"
      config_rule_version  = "<YYYY-MM-DD>"
      description          = "Description of what this rule checks"
      resource_types_scope = ["AWS::Service::ResourceType"]
    },
  ]
}
```

Add the same block to `cpack_encryption_use1` (USE1 region).

### Step 3 — Deploy

```bash
cd custom-config-rules/environments/prd
terraform plan   # review changes
terraform apply
```

### Step 4 — Verify

```bash
aws configservice describe-conformance-pack-compliance \
  --conformance-pack-name "<account-alias>-encryption-validation"
```

---

## 9. Updating an Existing Guard Rule

When a Guard rule needs logic changes:

1. **Create a new versioned file** — never edit an existing `.guard` file in-place.

   ```text
   policies/<rule-name>/<rule-name>-<new-date>.guard
   ```

2. **Update `config_rule_version`** in `cpack_encryption.tf` (both USE2 and USE1 modules).

3. Run `terraform plan` and `terraform apply`.

4. The old `.guard` file remains for audit history — do not delete it.

---

## 10. Checking Compliance Status

### AWS Console

1. AWS Config → Conformance Packs → `<account-alias>-encryption-validation`
2. View per-rule compliance percentages
3. Click into a rule to see individual non-compliant resources

### AWS CLI — Org Conformance Pack Summary

```bash
# Summary of all rules in the org pack
aws configservice describe-organization-conformance-pack-statuses \
  --organization-conformance-pack-names "<account-alias>-encryption-validation"

# Compliance summary per account
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name "<account-alias>-encryption-validation" \
  --filters Status=NON_COMPLIANT
```

### AWS CLI — Per-Rule, Per-Account

```bash
# Non-compliant EBS volumes in current account
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "<account-alias>-ebs-is-encrypted<random_id>" \
  --compliance-types NON_COMPLIANT

# Non-compliant SQS queues
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "<account-alias>-sqs-is-encrypted<random_id>" \
  --compliance-types NON_COMPLIANT

# Non-compliant EFS file systems (at-rest rule)
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "<account-alias>-efs-is-encrypted<random_id>" \
  --compliance-types NON_COMPLIANT

# Non-compliant EFS file systems (TLS rule — Lambda)
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "efstlsenforcement_<account_id>" \
  --compliance-types NON_COMPLIANT
```

> **Tip:** The `<random_id>` suffix on rule names is appended by the `conformance_pack` module to avoid naming collisions. Retrieve it from the AWS Console or with `aws configservice describe-config-rules`.

---

## 11. Troubleshooting

### 11.1 Org Conformance Pack Stuck in `CREATE_IN_PROGRESS`

**Cause:** Member account has Config recorder not started or S3 delivery channel not configured.

```bash
# Check status per account
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name "<account-alias>-encryption-validation" \
  --filters Status=CREATE_FAILED
```

**Resolution:**

- Ensure Config recorder and delivery channel are enabled in the failing account.
- If the account is a permanent exception, add the account ID to `excluded_accounts` in `cpack_encryption.tf` and re-apply.

---

### 11.2 Guard Rule Returns Unexpected NON_COMPLIANT

**Cause:** Config item attribute name mismatch (case-sensitive).

- EFS uses `configuration.Encrypted` (capital E) — not `configuration.encrypted`
- Verify the Config item schema in the AWS Console: Config → Resources → select resource → View Config item JSON

```bash
# Fetch Config item for a specific resource
aws configservice get-resource-config-history \
  --resource-type AWS::EFS::FileSystem \
  --resource-id <fs-id> \
  --limit 1
```

---

### 11.3 EFS TLS Lambda Rule — All Resources NON_COMPLIANT

**Cause:** EFS file system has no resource policy (no policy = no Deny on non-TLS).

**Resolution:** Attach a resource-based policy to the EFS that includes:

```json
{
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": { "AWS": "*" },
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

See [terraform-aft-account-customizations/modules/policy-files/efs_tls_compliance.json](terraform-aft-account-customizations/modules/policy-files/efs_tls_compliance.json) for the compliant policy reference.

---

### 11.4 Lambda Not Invoked by Config

**Cause:** Lambda resource-based policy missing permission for `config.amazonaws.com`.

```bash
# Check Lambda resource policy
aws lambda get-policy --function-name efs-tls-enforcement

# Expected principal: config.amazonaws.com
```

The Lambda module (`modules/lambda/main-iam.tf`) sets `principal = "config.amazonaws.com"` — re-apply AFT customization if missing.

---

### 11.5 OPA Mandatory Policy Blocking Pipeline Unexpectedly

**Scenario:** EFS resource has `encrypted = true` and `kms_key_id` set, but pipeline still fails.

**Check 1 — KMS ARN format:**

The mandatory policy requires `kms_key_id` to start with `arn:aws:kms:`. Aliases (`alias/my-key`) and short key IDs are rejected.

```hcl
# WRONG
kms_key_id = "alias/my-efs-key"

# CORRECT
kms_key_id = "arn:aws:kms:us-east-2:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Check 2 — Replication configuration:**

If the plan includes `aws_efs_replication_configuration`, every `destination` block must also have a `kms_key_id` set to a valid ARN.

---

### 11.6 New Account Not Receiving Lambda Config Rule

**Cause:** AFT customization pipeline did not complete successfully for the account.

**Check:**

```bash
# In the account — check if Lambda exists
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName,`efs-tls-enforcement`)]'

# Check conformance pack
aws configservice describe-conformance-packs \
  --query 'ConformancePackDetails[?ConformancePackName==`Lambdarulesconformancepack`]'
```

**Resolution:** Re-trigger the AFT customization pipeline for the account.
`<!-- PLACEHOLDER: Insert your AFT re-trigger steps here -->`

---

## 12. Excluded Accounts

Accounts excluded from org conformance packs are listed in:

File: [custom-config-rules/environments/prd/cpack_encryption.tf](custom-config-rules/environments/prd/cpack_encryption.tf)

```hcl
excluded_accounts = [
  "000000000000",      # <!-- PLACEHOLDER: account name / reason -->
  "066777777777",      # <!-- PLACEHOLDER: account name / reason -->
  "999999990618",      # <!-- PLACEHOLDER: account name / reason -->
  "666666666739"       # smrrnd-tst | config not config'd on account and SCP blocks it
]
```

Process to add an exclusion:

1. Add the account ID and a comment explaining the reason
2. Run `terraform plan` and verify the account appears in `excluded_accounts`
3. Run `terraform apply`
4. Document the exclusion in Jira: `<!-- PLACEHOLDER: Jira ticket for tracking exclusions -->`

> Exclusions should be treated as exceptions requiring re-review. Track them in Jira and review quarterly.

---

## 13. Variable Reference

### 13.1 custom-config-rules — conformance_pack module

| Variable | Type | Description | Default |
| --- | --- | --- | --- |
| `cpack_name` | `string` | Name of the conformance pack | required |
| `organization_pack` | `bool` | Deploy as org-level pack | `false` |
| `excluded_accounts` | `list(string)` | Account IDs excluded from org pack | `[]` |
| `policy_rules_list` | `list(object)` | Guard rules to include | `[]` |
| `lambda_rules_list` | `list(object)` | Lambda rules to include | `[]` |
| `managed_rules_list` | `list(object)` | AWS Managed rules to include | `[]` |

`policy_rules_list` object schema:

```hcl
{
  config_rule_name     = string   # matches policies/<name>/ directory
  config_rule_version  = string   # matches <name>-<version>.guard filename
  description          = string
  resource_types_scope = list(string)
  policy_runtime       = optional(string, "guard-2.x.x")
}
```

### 13.2 terraform-aft-account-customizations — exceptions/terraform

| Variable | Type | Description | Default |
| --- | --- | --- | --- |
| `account_name` | `string` | Name of the account being customized | required |
| `region` | `string` | Primary region | `us-east-1` |
| `environment` | `string` | Environment tag | `prd` |
| `kms_key_arn` | `string` | KMS key ARN for Lambda encryption | `null` |
| `enable_ebs_scp` | `bool` | Enable EBS governance SCP | `true` |
| `enable_sqs_scp` | `bool` | Enable SQS governance SCP | `true` |
| `enable_efs_scp` | `bool` | Enable EFS governance SCP | `true` |
| `scp_attach_to_target` | `bool` | Attach SCPs to OU/account | `false` |
| `scp_target_id` | `string` | OU or account ID for SCP attachment | `null` |

---

## 14. CCOPS — Cloud Ops Governance Platform

Repository: `AWS-Terraform-Playground/cloud-ops-governance-platform`

CCOPS acts as the **operational response layer** on top of AWS Config. It ingests compliance findings, runs them through a DynamoDB-driven rule engine, and raises ServiceNow incidents for confirmed violations.

### 14.1 Platform Data Flow

```text
AWS Config CSV Export
        │  uploaded to S3 raw/<source>/<accountId>_<accountName>_<ruleId>.csv
        ▼
complianceIngestLambda          (triggered by S3 EventBridge notification)
        │  parses CSV → INSERT IGNORE into MySQL RDS `ingest` table
        ▼
EventBridge Scheduler
        │  triggers on schedule
        ▼
complianceRulesExecutionLambda
        │  scans DynamoDB: FilterExpression enabled = true
        │  matches ingest rows against each rule's ingest_policy
        │  writes matched rows as CSV to S3 processed/<source>/<accountId>/<ruleId>_<date>.csv
        │  INSERT / UPDATE MySQL `actions` table (hash-based change detection)
        ▼
serviceNowEventManagerLambda    (triggered by Step Function)
        │  reads actions table + S3 artifact
        ▼
ServiceNow Incident (Create or Update)
```

### 14.2 DynamoDB Table

| Attribute | Value |
| --- | --- |
| **Table name** | `ccops-policy-engine-rules` |
| **Hash key** | `source` (String) |
| **Range key** | `id` (Number) |
| **Encryption** | KMS — `module.ccop_dynamodb_kms_key` |
| **Source file** | [cloud-ops-governance-platform/dynamo/rules.json](cloud-ops-governance-platform/dynamo/rules.json) |
| **Managed by** | Terraform `dynamodb.tf` — items loaded via `aws_dynamodb_table_item` |

Each item has the following attributes written to DynamoDB:

| DynamoDB Attribute | Type | Description |
| --- | --- | --- |
| `source` | String | Always `aws_config` for Config-sourced rules |
| `id` | Number | Unique rule ID |
| `description` | String | Human-readable rule description |
| `enabled` | Boolean | Whether the rule is actively processed |
| `ingest_policy` | String (JSON) | Filter: resource types, Config rule names, annotations, exclusions |
| `actions_policy` | String (JSON) | ServiceNow action details: type, assignment group, impact, urgency |

---

### 14.3 EBS Rule — item3 (id: 3)

Status: `enabled: false` — not yet generating incidents

Full JSON:

```json
{
  "source": "aws_config",
  "id": 3,
  "enabled": false,
  "description": "Matching on EBS Encryption",
  "actions_policy": {
    "Action": {
      "Target": "servicenow",
      "Type": "incident",
      "CallerId": "ccops",
      "AssignmentGroup": "cmdb:assignment_group",
      "ConfigurationItem": "aws_account",
      "Impact": 2,
      "Urgency": 3
    }
  },
  "ingest_policy": {
    "ResourceTypes": ["AWS::EC2::Volume"],
    "ComplianceType": "NON_COMPLIANT",
    "Rules": ["ebs-is-encrypted-conformance-pack"],
    "Annotations": ["EBS Volumes must be encrypted"],
    "Exclusions": []
  }
}
```

| Field | Value |
| --- | --- |
| **Config rule matched** | `ebs-is-encrypted-conformance-pack` |
| **Resource type** | `AWS::EC2::Volume` |
| **Annotation matched** | `EBS Volumes must be encrypted` |
| **ServiceNow Impact** | 2 |
| **ServiceNow Urgency** | 3 |
| **Exclusions** | None configured |

---

### 14.4 SQS Rule — item4 (id: 4)

Status: `enabled: false` — not yet generating incidents

Full JSON:

```json
{
  "source": "aws_config",
  "id": 4,
  "enabled": false,
  "description": "Matching on SQS in Rest Encryption",
  "actions_policy": {
    "Action": {
      "Target": "servicenow",
      "Type": "incident",
      "CallerId": "ccops",
      "AssignmentGroup": "cmdb:assignment_group",
      "ConfigurationItem": "aws_account",
      "Impact": 2,
      "Urgency": 3
    }
  },
  "ingest_policy": {
    "ResourceTypes": ["AWS::SQS::Queue"],
    "ComplianceType": "NON_COMPLIANT",
    "Rules": ["sqs-is-encrypted-conformance-pack"],
    "Annotations": ["SQS must be encrypted by SQS-managed (SSE-SQS) or KMS"]
  }
}
```

| Field | Value |
| --- | --- |
| **Config rule matched** | `sqs-is-encrypted-conformance-pack` |
| **Resource type** | `AWS::SQS::Queue` |
| **Annotation matched** | `SQS must be encrypted by SQS-managed (SSE-SQS) or KMS` |
| **ServiceNow Impact** | 2 |
| **ServiceNow Urgency** | 3 |
| **Exclusions** | Not configured (field absent) |

---

### 14.5 EFS Rule — item5 (id: 5)

Status: `enabled: true` — active, generating incidents

Full JSON:

```json
{
  "source": "aws_config",
  "id": 5,
  "enabled": true,
  "description": "Matching on EFS in Rest and in-transit Encryption",
  "actions_policy": {
    "Action": {
      "Target": "servicenow",
      "Type": "incident",
      "CallerId": "ccops",
      "AssignmentGroup": "cmdb:assignment_group",
      "ConfigurationItem": "aws_account",
      "Impact": 2,
      "Urgency": 3,
      "Priority": 4,
      "ShortDescription": "EFS in Rest Encryption Violations for AWS Account {$ACCOUNT_NAME$} {$ACCOUNT_NUMBER$}",
      "Description": "EFS encryption violations have been detected in AWS account {$ACCOUNT_NAME$}.\nPlease refer to the attached CSV file for a detailed list of non-compliant resources. To remediate, ensure that all listed EFS resources are brought into compliance by enabling encryption in accordance with security standards.\nFollow the step-by-step remediation guidance outlined in the following knowledge base article : https://sampleurl.com/23rtw4f/3rfwef"
    }
  },
  "ingest_policy": {
    "ResourceTypes": ["AWS::EFS::FileSystem"],
    "ComplianceType": "NON_COMPLIANT",
    "Rules": [
      "efs-is-encrypted-conformance-pack",
      "efatlsenforcement"
    ],
    "Annotations": [
      "EFS's must be encrypted",
      "EFS file system has no policy - TLS enforcement not configured",
      "EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)"
    ],
    "Exclusions": [
      {
        "Accounts": [],
        "Regions": [],
        "ResourceTypes": [],
        "ResourceIds": [],
        "ARNs": []
      }
    ]
  }
}
```

| Field | Value |
| --- | --- |
| **Config rules matched** | `efs-is-encrypted-conformance-pack` (Guard — at-rest) AND `efatlsenforcement` (Lambda — TLS) |
| **Resource type** | `AWS::EFS::FileSystem` |
| **Annotations matched** | 3 — covers no encryption, no policy, incomplete TLS policy |
| **ServiceNow Impact** | 2 |
| **ServiceNow Urgency** | 3 |
| **ServiceNow Priority** | 4 |
| **Short Description** | `EFS in Rest Encryption Violations for AWS Account {$ACCOUNT_NAME$} {$ACCOUNT_NUMBER$}` |
| **Exclusions** | Supported — Accounts, Regions, ResourceTypes, ResourceIds, ARNs (all currently empty) |

> The `{$ACCOUNT_NAME$}` and `{$ACCOUNT_NUMBER$}` tokens are substituted by `serviceNowEventManagerLambda` at runtime.

---

### 14.6 Activating EBS or SQS Rules

To enable item3 (EBS) or item4 (SQS) and begin generating ServiceNow incidents:

#### Step 1 — Update `rules.json`

Edit [cloud-ops-governance-platform/dynamo/rules.json](cloud-ops-governance-platform/dynamo/rules.json):

```json
"item3": {
  "enabled": true
}
```

#### Step 2 — Add Exclusions (recommended before enabling)

For EBS/SQS, populate the `Exclusions` block in `ingest_policy` before enabling, to prevent noise from known exceptions:

```json
"Exclusions": [
  {
    "Accounts": ["123456789012"],
    "Regions": [],
    "ResourceTypes": [],
    "ResourceIds": [],
    "ARNs": []
  }
]
```

#### Step 3 — Deploy via Terraform

```bash
cd AWS-Terraform-Playground/cloud-ops-governance-platform
terraform plan   # verify only the DynamoDB item changes
terraform apply
```

#### Step 4 — Verify the item in DynamoDB

```bash
aws dynamodb get-item \
  --table-name ccops-policy-engine-rules \
  --key '{"source": {"S": "aws_config"}, "id": {"N": "3"}}'
```

Confirm `"enabled": {"BOOL": true}` in the response.

---

### 14.7 Adding or Modifying Exclusions (EFS item5)

To exclude specific accounts, regions, or resource IDs from EFS CCOPS incidents, edit the `Exclusions` array in `item5` within `rules.json`:

```json
"Exclusions": [
  {
    "Accounts": ["111122223333"],
    "Regions": ["us-west-2"],
    "ResourceTypes": [],
    "ResourceIds": ["fs-0abc1234def56789a"],
    "ARNs": []
  }
]
```

Then run `terraform apply` to sync the change to DynamoDB.

> Exclusion changes take effect on the **next rule execution cycle** triggered by EventBridge Scheduler.

---

### 14.8 Checking CCOPS Rule Execution Status

```bash
# Scan DynamoDB for all enabled rules
aws dynamodb scan \
  --table-name ccops-policy-engine-rules \
  --filter-expression "#en = :val" \
  --expression-attribute-names '{"#en": "enabled"}' \
  --expression-attribute-values '{":val": {"BOOL": true}}'

# Check processed CSV artifacts in S3
aws s3 ls s3://<ccops-bucket>/processed/aws_config/<account_id>/ --recursive

# Check actions table via MySQL (connect to RDS)
# SELECT * FROM actions WHERE ruleId IN (3,4,5) ORDER BY timestamp DESC LIMIT 20;
```

---

## Document History

| Version | Date | Author | Change |
| --- | --- | --- | --- |
| 1.0 | 2026-04-05 | `<!-- PLACEHOLDER -->` | Initial creation |
