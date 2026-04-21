# global-advisory-policies

Advisory OPA policies for Terraform. These policies **never block** a plan — they emit warnings that are surfaced in CI/CD output to guide engineers toward best practices without interrupting delivery.

Reference: [OPA — Terraform | openpolicyagent.org](https://www.openpolicyagent.org/docs/terraform)

---

## What Is an Advisory Policy?

In OPA, a policy is advisory when it:

- Sets `default authz := true` so the plan is always approved
- Uses an `advice` or `warn` rule (a set of strings) instead of `deny`
- Is registered in `policies.hcl` with `enforcement_level = "advisory"`

```rego
package terraform.advisory.ebs.encryption

import rego.v1

# Never blocks — advisory only
default authz := true

advice contains msg if {
    some resource in ebs_volume_changes
    not resource.change.after.encrypted
    msg := sprintf("ADVISORY [EBS-ENC-001]: Volume '%s' is not encrypted.", [resource.name])
}
```

The CI pipeline reads `advice` and prints warnings. The plan still applies.

---

## Policies in This Folder

### EBS Encryption Advisory (`aws_ebs_001_advise_encryption.rego`)

| Rule ID | Resource | Check |
| --- | --- | --- |
| `EBS-ENC-001` | `aws_ebs_volume` | `encrypted = true` is set |
| `EBS-ENC-002` | `aws_instance` | `root_block_device.encrypted = true` |
| `EBS-ENC-003` | `aws_instance` | `ebs_block_device.encrypted = true` |

Package: `terraform.policies.aws_ebs_001_advise_encryption`

### Module Usage Advisories (`aws_*_001_advise_module_usage.rego`)

One policy per AWS service — advises engineers to use the approved internal Terraform module instead of configuring the resource directly at the root level.

Covered services: API Gateway, API Gateway V2, Athena, Autoscaling, CloudFront, CloudWatch, Cognito, DataSync, DynamoDB, EC2, ECR, ECS, EFS, ElastiCache, ELB, IAM, KMS, Lambda, RDS, RDS Aurora, RDS Proxy, S3.

---

## Folder Structure

```text
global-advisory-policies/
├── policies.hcl                              # OPA policy config (advisory enforcement)
├── aws_ebs_001_advise_encryption.rego        # EBS encryption advisory
├── aws_efs_001_advise_module_usage.rego      # Module usage advisory (EFS)
├── aws_ec2_001_advise_module_usage.rego      # Module usage advisory (EC2)
├── ... (one file per service)
├── utils/
│   ├── advise_module_usage.rego              # Shared helper for module-usage checks
│   └── tests/
│       ├── advise_module_usage_test.rego
│       └── mocks/
│           ├── advise_module_usage_pass_*.json
│           └── advise_module_usage_fail_*.json
└── tests/
    ├── aws_ebs_001_advise_encryption_test.rego
    ├── aws_s3_001_advise_module_usage_test.rego
    └── mocks/
        ├── aws_ebs_001_pass_encrypted.json
        ├── aws_ebs_001_fail_unencrypted.json
        ├── aws_s3_001_pass_root_resource_uses_module.json
        └── aws_s3_001_fail_root_resource_not_using_module.json
```

---

## How OPA Reads the Terraform Plan

OPA receives `terraform show -json` output as `input`. For each resource in `input.resource_changes`:

```text
input.resource_changes[i].type              # e.g. "aws_ebs_volume"
input.resource_changes[i].name              # e.g. "data_disk"
input.resource_changes[i].address           # e.g. "aws_ebs_volume.data_disk"
input.resource_changes[i].change.actions    # e.g. ["create"]
input.resource_changes[i].change.after      # proposed state — what you validate
```

Policies skip `delete` and `no-op` actions and only evaluate `create` and `update`.

---

## Running Tests

```bash
# All advisory policy tests
opa test . -v

# Single policy
opa test aws_ebs_001_advise_encryption.rego \
         tests/aws_ebs_001_advise_encryption_test.rego -v
```

Expected output:

```text
PASS: test_authz_is_true_for_advisory_policy
PASS: test_standalone_ebs_unencrypted_generates_advice
PASS: test_ec2_root_volume_unencrypted_generates_advice
PASS: test_ec2_attached_ebs_unencrypted_generates_advice
PASS: test_compliant_resources_have_no_advice
PASS: test_noncompliant_plan_score_matches_finding_count
```

## Evaluating Against a Plan

```bash
terraform show -json tfplan.binary > tfplan.json

# See all advisory warnings
opa eval \
  --data . \
  --input tfplan.json \
  "data.terraform.policies.aws_ebs_001_advise_encryption.warn"

# Check compliance score (0 = fully compliant)
opa eval \
  --data . \
  --input tfplan.json \
  "data.terraform.policies.aws_ebs_001_advise_encryption.score"
```

## Adding a New Advisory Policy

1. Create `aws_{service}_{sequence}_advise_{description}.rego` in this folder
2. Use package `terraform.policies.aws_{service}_{sequence}_advise_{description}`
3. Set `default authz := true`
4. Define a `warn` set rule with `sprintf` messages
5. Add a test file under `tests/` and mock JSONs under `tests/mocks/`
6. Register the policy in `policies.hcl` with `enforcement_level = "advisory"`
