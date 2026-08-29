# patch-outcome-observability

Terraform module deployed to every AFT-vended member account. Reads SSM Run
Command terminal-status events for `AWS-RunPatchBaseline` and writes one flat
JSON record per instance/command to the central patching S3 bucket, for every
outcome -- patched, failed, or not-attempted -- so Splunk can answer "did this
instance patch" for any instance, any time.

See `PAYLOAD-SPEC-patch-outcome-record.md` for the record shape and
`BUILD-INSTRUCTIONS-infrastructure.md` for the design rationale behind every
choice below.

**New to this module?** `RESOURCES.md` walks through every resource one by one
in plain language — start there.

## What this module does NOT do — and what the central account must change

It never creates or modifies the central S3 bucket, its bucket policy, the
KMS key, or the KMS key policy. Those are owned by the bucket owner in the
central account, and **the Lambda cannot write until that owner makes two
changes**:

| # | Where | Change | Required? |
|---|---|---|---|
| 1 | Central **bucket policy** | Add one `Allow s3:PutObject` on `<bucket>/<archive_s3_prefix>/*`, conditioned on `aws:PrincipalOrgID` **and** `ArnLike aws:PrincipalArn = arn:*:iam::*:role/<writer_role_name>` | **Always** |
| 2 | Central **KMS key policy** | Add one `Allow kms:GenerateDataKey`/`Encrypt`/`DescribeKey`, same two conditions | Only when the bucket's default encryption is SSE-KMS with a customer-managed key |

This module *renders* both statements, fully resolved, as the
`central_prerequisites` output:

```bash
terraform output -json central_prerequisites | jq
```

Complete copy-and-edit policy documents live next to it in
`central-prerequisites/sample-*.json` (full bucket policy, full KMS key
policy, plus the ACL-enabled and `kms:ViaService` variants).

**`central-prerequisites/README.md` is the runbook for the bucket owner** —
the preflight checks that decide whether those two statements are sufficient,
the Deny patterns that silently override them, the ACL case, and the
end-to-end verification with the canary. Three things it asks you to confirm
before going live:

- **Object Ownership.** `BucketOwnerEnforced` → leave `archive_object_acl`
  null (sending an ACL fails with `AccessControlListNotSupported`). ACLs
  enabled → writers must send `bucket-owner-full-control`, the bucket policy
  must also allow `s3:PutObjectAcl`, and **so must this module's
  `S3WriteOnly` statement, which today grants only `s3:PutObject`**. Without
  all three, every put returns 200 and the bucket owner cannot read its own
  objects — nothing errors anywhere.
- **The bucket's actual encryption key.** Set `archive_kms_key_arn` to the
  bucket's *own* CMK or leave it null. A third key encrypts the objects under
  something the `s3tofirehose` reader has no `kms:Decrypt` on: writers
  succeed, Splunk gets nothing.
- **Existing Deny statements.** A Deny requiring `aws:SourceVpce`, a specific
  SSE key id, or a fixed account list beats the Allow above. See §4 of the
  runbook.

The writer never gets `kms:Decrypt`, `s3:GetObject`, `s3:ListBucket` or
`s3:DeleteObject` — it cannot read back a single record it wrote.

## Module dependencies

This module composes two shared modules from `Terrafrom-AWS-Prasanth/`:

| Child module | Used for | Source (local dev path) |
|---|---|---|
| `terraform-aws-lambda` | the writer Lambda + its permissions | `../../../Terrafrom-AWS-Prasanth/terraform-aws-lambda` |
| `terraform-aws-sqs` (×2) | the target-DLQ and lambda-DLQ | `../../../Terrafrom-AWS-Prasanth/terraform-aws-sqs` |

Both are referenced by **relative path** for local development. Before a real
fleet deployment, repoint `source` at a versioned registry / git ref
(`git::…//terraform-aws-lambda?ref=vX.Y.Z`) so 450 accounts pin an exact
module version.

### Consequences of using the shared modules

- **AWS provider floor is `>= 6.0.0`** (the shared `terraform-aws-sqs` module
  declares it), up from the `>= 5.40.0` in `BUILD-INSTRUCTIONS`.
- **Names are account-alias prefixed.** The shared modules force
  `<account-alias>-<name>` on the Lambda and both queues, via an
  `iam:ListAccountAliases` lookup this module now also performs. The Lambda is
  therefore `<alias>-<name_prefix>-writer`, not `<name_prefix>-writer`.
- **A per-account S3 package bucket** (`<name_prefix>-pkg-<account-id>`) is
  created, because the shared Lambda module deploys only from S3 or a
  container image — it cannot take a local zip. `src/` is zipped and uploaded
  there; `source_code_hash` still drives redeploys.
- **DLQ encryption** is AWS-default SSE-SQS (the shared module doesn't expose
  `sqs_managed_sse_enabled`). Same outcome as the old explicit setting.

## Resources created

- 3 EventBridge rules (invocation success, invocation failure, command
  failure) on the default bus, plus 1 optional always-on canary rule
- `module.writer_lambda` — 1 Lambda function (`src/handler.py`, provided
  verbatim, do not modify), 1 `aws_s3_object` for its package, and one
  `aws_lambda_permission` per rule
- 1 S3 package bucket + public-access-block + ownership-controls + SSE config
- 1 explicit Lambda log group (retention) and 1 async invoke config
- 1 IAM execution role with an exact, fleet-wide-identical name
- `module.target_dlq` / `module.lambda_dlq` — 2 SQS queues, plus a
  hand-written `aws_sqs_queue_policy` giving EventBridge `sqs:SendMessage` on
  the target DLQ

Deploy with `rules_enabled = false` to leave it dormant (only the canary and
the idle package bucket live) and arm later by flipping that one variable.

## Testing

`tests/` holds a native `terraform test` suite (`terraform >= 1.9`). Every run
is `command = plan` against a mocked AWS provider -- no credentials, no cost:

```bash
terraform -chdir=modules/patch-outcome-observability init -backend=false
terraform -chdir=modules/patch-outcome-observability test
```

- `defaults.tftest.hcl` -- resource shape and wiring under default inputs
  (3 SSM rules + canary, DLQ naming, Lambda contract via the `lambda_config`
  output, locked-down package bucket, pinned role name, `central_prerequisites`).
- `toggles.tftest.hcl` -- every feature flag: dormant deploy, canary off,
  enrichment/tag env passthrough, `name_prefix` derivation, KMS key routing.
- `validation.tftest.hcl` -- every `variable` guard rail via `expect_failures`,
  including "you cannot drop `Terminated` from `invocation_failure_statuses`".

Test notes for the mock provider: `aws_iam_policy_document` JSON, the account
alias, and `aws_lambda_function.function_name` (Optional+Computed) are all
unknowable at mock plan, so the test files pin them with `override_data` /
`override_resource` and assert Lambda internals through the shared module's
`lambda_config` output. A real-provider `plan` is still the final check before
arming a fleet.

## Refactor notes

- The three SSM EventBridge resources are addressed as
  `aws_cloudwatch_event_rule.ssm` (and `.ssm` target) to read cleanly next to
  the `.canary` siblings. No `moved` blocks are shipped -- this module has not
  been deployed anywhere yet.
- The shared `terraform-aws-lambda` module had to be repaired to be usable at
  all (an unescaped-quote syntax error, a broken `aws_schemas_schema`
  argument, an invalid `package_type` default, and unpinned providers). Two
  small outputs (`lambda_config`, `lambda_function_name`) were added so
  consumers can assert on what they deployed.

## Usage

```hcl
module "patch_outcome_observability" {
  source = "../../modules/patch-outcome-observability"

  archive_bucket_name = "central-patching-logs-bucket"
  archive_kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/xxxxxxxx"

  rules_enabled = true
  tags = {
    Team = "platform-engineering"
  }
}
```

## Open questions (see BUILD-INSTRUCTIONS section 9)

1. Is the central bucket `BucketOwnerEnforced`, or does it have ACLs enabled?
   Decides `archive_object_acl`.
2. Does the existing bucket policy contain an explicit `Deny` that would
   catch the writer role?
3. Do SCPs or permissions boundaries restrict `lambda:CreateFunction`,
   mandate a boundary, require a role path, or force Lambda into a VPC?
4. Is `command_id` an extracted field on the stdout sourcetype, or does it
   need a `rex` on the object path?
5. Does Splunk have an instance-ID -> owner lookup? If yes, set
   `include_instance_tags = false`.
