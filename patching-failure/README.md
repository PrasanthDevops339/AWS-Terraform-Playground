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
- `central-prerequisites/README.md` -- the two statements the CENTRAL
  bucket owner must merge (bucket policy + KMS key policy). This repo never
  creates or modifies the bucket, its policy, or the key.
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

Read the module's own README for the full variable list, resource shape,
and outstanding open questions that need answers before going live in
production (Object Ownership on the bucket, explicit Denies, SCP/VPC
constraints, Splunk field extraction, and the instance-tag lookup).
