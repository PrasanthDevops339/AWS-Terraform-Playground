# OPA Policy: EBS Encryption Advisory

This policy follows the official OPA Terraform pattern of evaluating a Terraform plan JSON file produced by `terraform show -json` and exposing a decision under the `terraform/analysis/...` namespace.

## What it checks

The policy emits **advisory** findings for:

- standalone `aws_ebs_volume` resources with `encrypted != true`
- EC2 `root_block_device` blocks with `encrypted != true`
- EC2 `ebs_block_device` blocks with `encrypted != true`

## Why this is advisory

This bundle is intentionally non-blocking:

- `data.terraform.analysis.authz` always returns `true`
- `data.terraform.analysis.advice` contains human-readable recommendations
- `data.terraform.analysis.findings` contains structured advisory output
- `data.terraform.analysis.score` equals the number of advisory findings

## Files

- `ebs_encryption_advisory.rego` — main policy
- `ebs_encryption_advisory_test.rego` — unit tests
- `tfplan_compliant.json` — sample Terraform plan with encrypted EBS settings
- `tfplan_noncompliant.json` — sample Terraform plan with unencrypted EBS settings

## Evaluate with OPA

```bash
opa eval \
  --data Terrafrom-OPA-Prasanth/EBS-Encryption-Advisory-OPA/ebs_encryption_advisory.rego \
  --input Terrafrom-OPA-Prasanth/EBS-Encryption-Advisory-OPA/tfplan_compliant.json \
  'data.terraform.analysis.advice'

opa eval \
  --data Terrafrom-OPA-Prasanth/EBS-Encryption-Advisory-OPA/ebs_encryption_advisory.rego \
  --input Terrafrom-OPA-Prasanth/EBS-Encryption-Advisory-OPA/tfplan_noncompliant.json \
  'data.terraform.analysis.findings'
```

## Test with OPA

```bash
opa test Terrafrom-OPA-Prasanth/EBS-Encryption-Advisory-OPA/ebs_encryption_advisory.rego \
  Terrafrom-OPA-Prasanth/EBS-Encryption-Advisory-OPA/ebs_encryption_advisory_test.rego -v
```

## Terraform workflow

```bash
terraform plan --out tfplan.binary
terraform show -json tfplan.binary > tfplan.json

opa eval --data Terrafrom-OPA-Prasanth/EBS-Encryption-Advisory-OPA/ebs_encryption_advisory.rego \
  --input tfplan.json \
  'data.terraform.analysis.advice'
```

## Notes

OPA's Terraform documentation notes that some values may be unknown at plan time. This policy therefore checks only values that are explicitly present in `resource_changes[].change.after` and focuses on create/update actions.
