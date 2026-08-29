# Patch Outcome Observability

Terraform for shipping per-instance SSM patch outcome records (patched /
failed / not-attempted) from every AFT-vended member account into the
central patching S3 bucket, for Splunk.

- `PAYLOAD-SPEC-patch-outcome-record.md` -- the record shape, the three
  outcome classes, and the searches ops runs against it.
- `BUILD-INSTRUCTIONS-infrastructure.md` -- the infrastructure design and
  the constraints behind every choice in the module.
- `modules/patch-outcome-observability/` -- the Terraform module. Deployed
  once per region, per account.
- `central-prerequisites/README.md` -- **the runbook for the central
  account**: the two statements the bucket owner must merge (bucket policy +
  KMS key policy), the preflight checks that decide whether they are enough,
  the Deny patterns that silently override them, and how to verify the write
  path end to end. This repo never creates or modifies the bucket, its
  policy, or the key.
- `examples/aft-account-customizations/main.tf` -- example wiring for an AFT
  account-customizations repo.
- `splunk/` -- `props.conf` sourcetype stanza and the
  `patch_outcome_action.csv` lookup table for the `recommended_action`
  field.

## Quick start

```hcl
module "patch_outcome_observability" {
  source = "./modules/patch-outcome-observability"

  archive_bucket_name = "<central bucket>"
  archive_kms_key_arn = "<central CMK arn>"
  rules_enabled       = false   # deploy dormant, arm later
}
```

## Changes required on the central bucket and its KMS key

Nothing here works until the central account merges two policy statements —
the Lambda writes cross-account, so its own IAM permissions are only half the
grant:

| # | Where | Change | Required? |
|---|---|---|---|
| 1 | Central **bucket policy** | `Allow s3:PutObject` on `<bucket>/patchingsolution-events/outcomes/*`, conditioned on `aws:PrincipalOrgID` **and** `ArnLike aws:PrincipalArn = arn:aws:iam::*:role/patch-outcome-s3-writer` | **Always** |
| 2 | Central **KMS key policy** | `Allow kms:GenerateDataKey` / `kms:Encrypt` / `kms:DescribeKey`, same two conditions, no `kms:Decrypt` | Only if the bucket is SSE-KMS with a customer-managed key |

Both are rendered fully resolved by the module
(`terraform output -json central_prerequisites | jq`), and
`central-prerequisites/sample-*.json` holds complete copy-and-edit policy
documents — the full bucket policy and the full KMS key policy with the new
statement merged in among plausible existing ones, plus the ACL and
`kms:ViaService` variants.

Three answers are needed back from the bucket owner before going live: the
bucket's **Object Ownership** setting (decides `archive_object_acl`), the
bucket's **own KMS key ARN** or "SSE-S3, no key" (decides
`archive_kms_key_arn`), and whether any existing **Deny** catches the writer
role. `central-prerequisites/README.md` has the commands, the failure modes —
including the two that fail silently with HTTP 200 — and the canary-based
verification.

Read the module's own README for the full variable list, resource shape,
and outstanding open questions that need answers before going live in
production (Object Ownership on the bucket, explicit Denies, SCP/VPC
constraints, Splunk field extraction, and the instance-tag lookup).
