# global-manadatery-policies

Mandatory OPA policies for Terraform. These policies **block** a plan when a violation is found. A non-empty `deny` set causes the CI/CD gate to fail and prevents `terraform apply` from running.

Reference: [OPA — Terraform | openpolicyagent.org](https://www.openpolicyagent.org/docs/terraform)

---

## What Is a Mandatory Policy?

In OPA, a policy is mandatory when it:

- Uses a `deny` rule that produces violation messages for non-compliant resources
- Returns a non-empty set to signal that the plan must be rejected
- Is registered in the CI gate with hard enforcement (pipeline fails on any denial)

```rego
package terraform.mandatory.efs.encryption

import rego.v1

deny contains msg if {
    some resource in efs_file_systems
    not resource.change.after.encrypted
    msg := sprintf("DENY [EFS-ENC-001]: EFS '%s' must have encrypted = true.", [resource.name])
}
```

If `deny` is non-empty, the pipeline fails and the plan is not applied.

---

## Policies in This Folder

### EFS KMS Encryption (`aws_efs_001_mandatory_encryption.rego`)

| Rule ID | Resource | Check |
| --- | --- | --- |
| `EFS-ENC-001` | `aws_efs_file_system` | `encrypted = true` |
| `EFS-ENC-002` | `aws_efs_file_system` | `kms_key_id` is set and non-null (customer-managed CMK) |
| `EFS-ENC-003` | `aws_efs_file_system` | `kms_key_id` starts with `arn:aws:kms:` |
| `EFS-ENC-004` | `aws_efs_replication_configuration` | Every replication destination has a `kms_key_id` |

Package: `terraform.policies.aws_efs_001_mandatory_encryption`

Severity: **HIGH** — blocks the plan on any violation.

**Why customer-managed KMS?** AWS default keys (`aws/elasticfilesystem`) do not support cross-account access or custom key policies. A customer-managed CMK is required for compliance with CIS AWS 2.4.1 and AWS Well-Architected SEC08-BP02.

---

## Folder Structure

```text
global-manadatery-policies/
├── aws_efs_001_mandatory_encryption.rego       # EFS KMS encryption enforcement
└── tests/
    ├── aws_efs_001_mandatory_encryption_test.rego
    └── mocks/
        ├── aws_efs_001_pass_compliant.json     # EFS with encrypted=true + valid KMS ARN
        └── aws_efs_001_fail_noncompliant.json  # EFS with encrypted=false + null kms_key_id
```

---

## How OPA Reads the Terraform Plan

OPA receives `terraform show -json` output as `input`. Mandatory policies iterate `input.resource_changes` and only evaluate `create` and `update` actions:

```text
input.resource_changes[i].type              # e.g. "aws_efs_file_system"
input.resource_changes[i].name              # e.g. "main"
input.resource_changes[i].address           # e.g. "module.efs.aws_efs_file_system.main"
input.resource_changes[i].change.actions    # e.g. ["create"]
input.resource_changes[i].change.after      # proposed state — what you validate
```

`delete` and `no-op` actions are skipped — the policy only enforces what is being created or changed.

---

## Running Tests

```bash
# All mandatory policy tests
opa test . -v

# Single policy
opa test aws_efs_001_mandatory_encryption.rego \
         tests/aws_efs_001_mandatory_encryption_test.rego -v
```

Expected output (24 tests):

```text
PASS: test_compliant_efs_passes
PASS: test_compliant_efs_is_compliant
PASS: test_unencrypted_efs_denied
PASS: test_unencrypted_efs_has_correct_code
PASS: test_null_kms_key_denied
PASS: test_null_kms_key_has_correct_code
PASS: test_empty_kms_key_denied
PASS: test_empty_kms_key_has_correct_code
PASS: test_bad_arn_denied
PASS: test_bad_arn_has_correct_code
PASS: test_replication_no_kms_denied
PASS: test_replication_no_kms_has_correct_code
PASS: test_replication_with_kms_passes
PASS: test_delete_action_ignored
PASS: test_noop_action_ignored
PASS: test_no_efs_resources_passes
PASS: test_no_efs_is_compliant
PASS: test_mixed_plan_has_one_denial
PASS: test_mixed_plan_targets_bad_resource
PASS: test_metadata_exists
PASS: test_metadata_severity_high
PASS: test_metadata_enforcement_mandatory
```

## Evaluating Against a Real Plan

```bash
terraform show -json tfplan.binary > tfplan.json

# Check for violations — non-empty output = plan is blocked
opa eval \
  --data . \
  --input tfplan.json \
  "data.terraform.policies.aws_efs_001_mandatory_encryption.deny"

# Check compliance boolean
opa eval \
  --data . \
  --input tfplan.json \
  "data.terraform.policies.aws_efs_001_mandatory_encryption.compliant"
```

## Adding a New Mandatory Policy

1. Create `aws_{service}_{sequence}_mandatory_{description}.rego` in this folder
2. Use package `terraform.policies.aws_{service}_{sequence}_mandatory_{description}`
3. Define a `deny` set rule — each entry is a violation message string
4. Add a `compliant` rule: `compliant if { count(deny) == 0 }`
5. Add a `metadata` object with `name`, `version`, `severity`, `enforcement: "mandatory"`
6. Add a test file under `tests/` and mock JSONs under `tests/mocks/`
