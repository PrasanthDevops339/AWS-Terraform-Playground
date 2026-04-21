# Terraform OPA Policies

This repository contains Open Policy Agent (OPA) policies that gate Terraform plans in CI/CD pipelines. Policies are evaluated against the JSON output of `terraform show -json` before any infrastructure change is applied.

Reference: [OPA — Terraform | openpolicyagent.org](https://www.openpolicyagent.org/docs/terraform)

---

## How It Works

```bash
terraform plan -out=tfplan.binary
terraform show -json tfplan.binary > tfplan.json
opa eval --data <policy_dir> --input tfplan.json "data.<package>.<rule>"
```

OPA receives the Terraform plan as `input`. The key field is `input.resource_changes` — an array of every resource being created, updated, or destroyed.

### Terraform Plan JSON Structure

```json
{
  "resource_changes": [
    {
      "address": "aws_efs_file_system.main",
      "type":    "aws_efs_file_system",
      "name":    "main",
      "change": {
        "actions": ["create"],
        "before":  null,
        "after": {
          "encrypted":  true,
          "kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/..."
        }
      }
    }
  ]
}
```

| Field | Description |
| --- | --- |
| `resource_changes` | All resources being changed by the plan |
| `change.actions` | `["create"]`, `["update"]`, `["delete"]`, `["no-op"]` |
| `change.before` | State before the change (`null` for creates) |
| `change.after` | Proposed state after the change (what you validate) |

Policies **only evaluate `create` and `update` actions** — `delete` and `no-op` are skipped.

---

## Repository Structure

```text
Terrafrom-OPA-Prasanth/
├── global-advisory-policies/    # Warn-only — never blocks a plan
│   ├── aws_ebs_001_advise_encryption.rego
│   ├── aws_efs_001_advise_module_usage.rego
│   ├── aws_ec2_001_advise_module_usage.rego
│   ├── ... (module-usage advisories for all AWS services)
│   ├── policies.hcl             # OPA policy config (enforcement_level = advisory)
│   ├── tests/
│   │   ├── aws_ebs_001_advise_encryption_test.rego
│   │   ├── aws_s3_001_advise_module_usage_test.rego
│   │   └── mocks/               # Terraform plan JSON fixtures
│   └── utils/
│       ├── advise_module_usage.rego
│       └── tests/
│
└── global-manadatery-policies/  # Hard enforcement — blocks a non-compliant plan
    ├── aws_efs_001_mandatory_encryption.rego
    ├── policies.hcl             # OPA policy config (enforcement_level = mandatory)
    └── tests/
        ├── aws_efs_001_mandatory_encryption_test.rego
        └── mocks/               # Terraform plan JSON fixtures
```

---

## Policy Enforcement Levels

| Folder | Level | Effect | Rego rule |
| --- | --- | --- | --- |
| `global-advisory-policies` | Advisory | Pipeline warns but **does not block** | `warn`, `authz := true` |
| `global-manadatery-policies` | Mandatory | Pipeline **blocks** on violation | `deny` |

---

## Running Tests

```bash
# Run all tests in a folder
opa test global-advisory-policies/ -v
opa test global-manadatery-policies/ -v

# Run tests for a specific policy
opa test global-advisory-policies/aws_ebs_001_advise_encryption.rego \
         global-advisory-policies/tests/aws_ebs_001_advise_encryption_test.rego -v
```

## Evaluating Against a Real Plan

```bash
# Advisory — check warn output
terraform show -json tfplan.binary > tfplan.json

opa eval \
  --data global-advisory-policies/ \
  --input tfplan.json \
  "data.terraform.policies.aws_ebs_001_advise_encryption.warn"

# Mandatory — check deny output (non-empty = blocked)
opa eval \
  --data global-manadatery-policies/ \
  --input tfplan.json \
  "data.terraform.policies.aws_efs_001_mandatory_encryption.deny"
```

## Naming Convention

```text
aws_{service}_{sequence}_{advise|mandatory}_{description}.rego
```

| Segment | Example | Meaning |
| --- | --- | --- |
| `aws` | `aws` | AWS provider |
| `{service}` | `ebs`, `efs`, `s3` | AWS service |
| `{sequence}` | `001` | Policy number per service |
| `{advise or mandatory}` | `advise` / `mandatory` | Enforcement level |
| `{description}` | `encryption`, `module_usage` | What is being checked |

Mock JSON files follow the same convention:

```text
aws_{service}_{sequence}_{pass|fail}_{description}.json
```
