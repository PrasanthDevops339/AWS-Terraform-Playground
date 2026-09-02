# BUILD INSTRUCTIONS — Patch Outcome Observability (infrastructure)

**For:** a coding agent (Claude Code) building the Terraform.
**Companion documents:** `PAYLOAD-SPEC-patch-outcome-record.md` (what the Lambda writes — read it), `PROPOSAL-patch-failure-observability.md` (why — read only if you need context).

---

## 0. Before you start

**Read `PAYLOAD-SPEC-patch-outcome-record.md` first.** It defines the record, the three outcome classes and the three EventBridge rules. This document builds the infrastructure that carries it.

**`src/handler.py` is already written and tested. Use it verbatim. Do not rewrite, refactor, reformat or "improve" it.** If it is not present in the repo, stop and ask — do not reconstruct it from the payload spec.

**Section 8 lists things that will look like improvements and are not.** Read it before writing code.

### What already exists — do not create these

| Exists | Where |
|---|---|
| Central S3 bucket for patching logs | Central account (bucket owner) |
| KMS CMK encrypting that bucket | Central account |
| Bucket policy carrying the org-scoped AFT statement | Central account |
| `s3tofirehose` ingestion into Splunk | Owned by another team |

This module **never** creates or modifies a bucket, a bucket policy, a KMS key or a KMS key policy. It renders the two statements the bucket owner must merge, as Terraform **outputs** only.

### Deployment context

- Deployed to ~450 AFT-vended accounts via **AFT account customizations**
- Single region per deployment. Multi-region means deploying the module once per region.
- Must be deployable **dormant** (`rules_enabled = false`) and armed later by flipping one variable
- Cost at rest must be $0

---

## 1. Repo layout to produce

```
modules/patch-outcome-observability/
    main.tf
    variables.tf
    outputs.tf
    versions.tf
    README.md
    src/handler.py              # PROVIDED — do not modify
central-prerequisites/README.md # the two statements the bucket owner merges
examples/aft-account-customizations/main.tf
splunk/props.conf
splunk/patch_outcome_action.csv
README.md
```

---

## 2. Provider constraints

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws     = { source = "hashicorp/aws",     version = ">= 5.40.0, < 7.0.0" }
    archive = { source = "hashicorp/archive", version = ">= 2.4.0" }
  }
}
```

Do **not** use `data.aws_region.current.name` — deprecated in provider 6.x, and `.region` does not exist in 5.x. Derive region and partition by splitting an ARN you already own (the Lambda log group ARN).

---

## 3. EventBridge — three rules plus an optional canary

All rules on the **default** bus. SSM service events are delivered nowhere else. Build patterns with `jsonencode()`, not heredocs. Use `state`, not the deprecated `is_enabled`.

| Key | detail-type | `detail.status` |
|---|---|---|
| `invocation_success` | `EC2 Command Invocation Status-change Notification` | `["Success"]` |
| `invocation_failure` | `EC2 Command Invocation Status-change Notification` | `["Failed","TimedOut","Cancelled","Undeliverable","Terminated"]` |
| `command_failure` | `EC2 Command Status-change Notification` | `["Failed","TimedOut","Cancelled","Undeliverable","Incomplete","AccessDenied","DeliveryTimedOut"]` |

Every pattern also carries:

```json
"source": ["aws.ssm"],
"detail": { "document-name": [{ "prefix": "AWS-RunPatchBaseline" }] }
```

**All three target the same Lambda.** The success rule is not optional — without a success record, an instance that patched cleanly returns nothing in Splunk, which ops cannot distinguish from a broken pipeline.

Naming: `${var.name_prefix}-${replace(key, "_", "-")}`.
State: `var.rules_enabled ? "ENABLED" : "DISABLED"`.

Every target gets `dead_letter_config` pointing at the **target DLQ** (section 6).

### Canary rule — `var.enable_canary`, default `true`

Separate rule, always `ENABLED` regardless of `rules_enabled`, matching:

```json
{ "source": ["custom.patch-canary"] }
```

Same Lambda target. `PutEvents` rejects any source beginning with `aws.`, so a canary cannot impersonate a real SSM event — it proves the plumbing (Lambda, role, bucket policy, KMS grant), not the event pattern. With no metrics tier, this is the **only** end-to-end liveness proof for a solution that sits dormant.

---

## 4. Lambda

| Setting | Value |
|---|---|
| Name | `${var.name_prefix}-writer` |
| Runtime | `python3.13` |
| Handler | `handler.handler` |
| Memory | 128 MB |
| Timeout | 30 s |
| Package | `data "archive_file"` → `source_file = "${path.module}/src/handler.py"`, `output_path = "${path.module}/build/handler.zip"` |
| `source_code_hash` | `data.archive_file.this.output_base64sha256` — **required**, or code updates never deploy |
| Reserved concurrency | `var.reserved_concurrency`, default `null` — omit the argument when null |
| VPC config | **none.** See section 9 question 3. |

`.gitignore` must exclude `modules/**/build/`.

### Environment variables

| Var | Value |
|---|---|
| `BUCKET_NAME` | `var.archive_bucket_name` |
| `S3_PREFIX` | `var.archive_s3_prefix` |
| `KMS_KEY_ARN` | `var.archive_kms_key_arn` |
| `OBJECT_ACL` | `var.archive_object_acl` (empty string when null) |
| `ENRICH` | `tostring(var.enable_enrichment)` |
| `INCLUDE_INSTANCE_TAGS` | `tostring(var.include_instance_tags)` |
| `LOG_LEVEL` | `var.log_level` |

### Log group

Declare explicitly at `/aws/lambda/${function_name}` with `retention_in_days = var.lambda_log_retention_in_days` (default 365 — this is the in-account triage tier, not a debug log). Add `depends_on` from the function to the log group so Terraform creates it before Lambda would auto-create it.

**Do not encrypt it with `archive_kms_key_arn`.** That key lives in the *central* account; using it here needs a cross-account grant for `logs.<region>.amazonaws.com` in 450 accounts. Use `var.local_kms_key_arn` if the org has a member-account key, otherwise leave default encryption.

### Invocation permission

One `aws_lambda_permission` per rule (including the canary), `principal = "events.amazonaws.com"`, `source_arn` = that rule's ARN, unique `statement_id`. **Not a role** — EventBridge→Lambda uses a resource policy.

### Async failure destination

```hcl
resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600
  destination_config {
    on_failure { destination = aws_sqs_queue.lambda_dlq.arn }
  }
}
```

---

## 5. IAM execution role — the name is load-bearing

```hcl
name = var.writer_role_name   # default "patch-outcome-s3-writer"
```

**Identical in every account**, because the central bucket and KMS policies authorise it with `ArnLike arn:<partition>:iam::*:role/<name>`. Do not derive it from `name_prefix`, do not append a suffix, do not let Terraform randomise it. Validate it contains no `*` or `/`.

> This is the opposite of the AFT-vended instance profiles, which carry generated suffixes and *forced* a wildcard. Here you control the name, so pin it.

Support `var.iam_role_path` and `var.permissions_boundary_arn`.

### Inline policy — least privilege

| Action | Resource |
|---|---|
| `logs:CreateLogStream`, `logs:PutLogEvents` | its own log group ARN + `:*` |
| `s3:PutObject` | `arn:<p>:s3:::<bucket>/<prefix>/*` — **nothing wider**, no bucket-level actions, no `s3:*` |
| `kms:GenerateDataKey`, `kms:Encrypt`, `kms:DescribeKey` | `var.archive_kms_key_arn` — only when set. **No `kms:Decrypt`; this path only writes.** |
| `sqs:SendMessage` | the Lambda failure DLQ ARN |
| `ssm:GetCommandInvocation` | `*` — the API has no resource-level scoping |
| `ssm:ListCommands` | `*` |
| `ssm:DescribeInstanceInformation` | `*` |
| `ec2:DescribeInstances` | `*` — only when `var.include_instance_tags` is true |

Everything is read-only except the single S3 write.

---

## 6. Two DLQs — different failure points, both required

| Queue | Catches | Attached to |
|---|---|---|
| `${name_prefix}-target-dlq` | *"EventBridge could not invoke the Lambda"* — permission revoked, function deleted | `dead_letter_config` on **every** event target |
| `${name_prefix}-lambda-dlq` | *"the function ran and threw"* — bucket policy, KMS grant, S3 error | `aws_lambda_function_event_invoke_config` `on_failure` |

Both: `message_retention_seconds = 1209600` (14 days).

**Encryption: use `sqs_managed_sse_enabled = true`.** Do **not** use `archive_kms_key_arn` — that key is in the central account and SSE-SQS is free, in-account and sufficient here.

Target DLQ needs a queue policy allowing `events.amazonaws.com` to `sqs:SendMessage`, conditioned:

```
ArnLike      aws:SourceArn     = arn:<partition>:events:*:<account>:rule/${name_prefix}-*
StringEquals aws:SourceAccount = <account>
```

> With no metrics tier, these two queues plus the canary are the entire safety net. They are not optional hardening.

---

## 7. Variables

| Variable | Type | Default | Notes |
|---|---|---|---|
| `name_prefix` | string | `patch-outcome` | regex `^[a-z0-9][a-z0-9-]{2,40}$` |
| **`archive_bucket_name`** | string | *(required)* | existing central bucket. Do not create it. |
| `archive_s3_prefix` | string | `patchingsolution-events/outcomes` | **sibling** of `patchingsolution/`, not a child — see below. Reject leading/trailing `/`. |
| `archive_kms_key_arn` | string | `null` | the **central** CMK. Used for the S3 write only. |
| `archive_object_acl` | string | `null` | `bucket-owner-full-control` **only** if the bucket has ACLs enabled. Section 9 q1. |
| `writer_role_name` | string | `patch-outcome-s3-writer` | **identical fleet-wide.** Reject `*` and `/`. |
| `patch_document_name_prefix` | string | `AWS-RunPatchBaseline` | prefix match also catches `…Association` |
| `invocation_failure_statuses` | list(string) | see §3 | **do not remove `Terminated`** |
| `command_failure_statuses` | list(string) | see §3 | |
| `rules_enabled` | bool | `true` | `false` = deploy dormant |
| `enable_canary` | bool | `true` | |
| `enable_enrichment` | bool | `true` | **do not disable in production** — the only source of `Terminated` |
| `include_instance_tags` | bool | `true` | set `false` if Splunk has an instance-ID → owner lookup |
| `lambda_log_retention_in_days` | number | `365` | validate against the CloudWatch allowed list |
| `local_kms_key_arn` | string | `null` | member-account key for the log group. **Not** the central archive key. |
| `reserved_concurrency` | number | `null` | |
| `log_level` | string | `INFO` | |
| `iam_role_path` | string | `/` | |
| `permissions_boundary_arn` | string | `null` | |
| `tags` | map(string) | `{}` | |

Allowed retention values: `1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1096,1827,2192,2557,2922,3288,3653`

### Why the prefix is a sibling

`patchingsolution-events/outcomes` sits **beside** `patchingsolution/`, not inside it. If `s3tofirehose` matches on the `patchingsolution/` prefix, dropping JSON inside it makes the labeling script tag these records with the RunPatchBaseline **stdout** sourcetype. They parse as garbage into the wrong index — which looks like success from the AWS side and is worse than never arriving. Put this rationale in the variable description.

---

## 8. MUST NOT

| Do not | Why |
|---|---|
| Rewrite, refactor or reformat `src/handler.py` | It is written and tested. Use verbatim. |
| Create any custom CloudWatch metric, metric filter or EMF output | Deliberately removed. Detection and alerting live in Splunk. |
| Create `aws_s3_bucket`, `aws_s3_bucket_policy`, `aws_kms_key` or `aws_kms_key_policy` | They exist. The bucket policy carries the AFT org-scoped statement; owning it in Terraform would replace and break it. Render statements as outputs. |
| Create an `aws_s3_bucket_notification` | Authoritative per bucket. A second one silently wipes the existing config and breaks ingestion for every account. |
| Introduce a custom or central EventBridge bus | Everything is in-account. The only cross-account hop is `PutObject`. |
| Put the rules on anything but the default bus | AWS service events are delivered there only. |
| Drop the `invocation_success` rule, or point it somewhere other than the Lambda | Without a success record, a cleanly patched instance returns nothing in Splunk — indistinguishable from a broken pipeline. |
| Remove `Terminated` from `invocation_failure_statuses` | Zero-tolerance rate control is deliberate policy. A `Terminated` instance is **unpatched**, and unpatched is a failure. |
| Use `archive_kms_key_arn` for the SQS queues or the Lambda log group | That key is in the *central* account. Member-account resources use SSE-SQS and `local_kms_key_arn`. |
| Grant `kms:Decrypt`, `s3:*`, or bucket-level S3 actions | Write-only path. `s3:PutObject` on the prefix, nothing else. |
| Derive, randomise or suffix `writer_role_name` | Central policies match `ArnLike …:role/<exact-name>` across 450 accounts. |
| Use a role for the EventBridge→Lambda target | Use `aws_lambda_permission`. A role is for cross-service targets like buses and Firehose. |
| Omit `source_code_hash` | Code changes will silently never deploy. |
| Treat the canary or the DLQs as optional | With no metrics tier there is one delivery path. They are the entire safety net. |
| Set reserved concurrency by default | Throttles exactly when zero tolerance produces its ~37-events-at-once burst. |
| Add SNS, SES, email, or any alerting logic | The org has none, and Splunk owns notification after ingest. |
| Add a Lambda layer, `requirements.txt` or a build step | boto3 ships in the runtime. Zero dependencies is the design. |
| Add VPC config to the Lambda | Only if section 9 q3 says guardrails force it — and then it needs S3 gateway + KMS interface endpoints. |

---

## 9. Open questions — surface these, do not guess

1. **Object Ownership on the bucket** — `BucketOwnerEnforced`, or ACLs enabled? Decides `archive_object_acl`. **Highest-risk unknown:** with ACLs enabled and no `bucket-owner-full-control`, every `PutObject` returns 200, objects accumulate, and the bucket owner gets AccessDenied reading its own bucket. Nothing errors anywhere.
2. **Does the existing bucket policy contain an explicit `Deny`** that would catch the writer role?
3. **Do SCPs or permissions boundaries restrict `lambda:CreateFunction`,** mandate a boundary, require a role path, or force Lambda into a VPC?
4. **Is `command_id` an extracted field on the stdout sourcetype**, or does it need a `rex` on the object path? Every drill-down search depends on it.
5. **Does Splunk have an instance-ID → owner lookup?** If yes, set `include_instance_tags = false`.

---

## 10. Outputs

`event_rule_arns`, `lambda_function_arn`, `lambda_function_name`, `lambda_log_group_name`, `lambda_package_bucket`, `writer_lambda_config`, `writer_role_arn`, `target_dlq_url`, `lambda_dlq_url`, `archive_s3_destination`, `canary_command`.

`writer_lambda_config` is the function contract this module hands the shared `terraform-aws-lambda` module — runtime, handler, sizing, package type and the environment map. It exists so the contract is asserted in one place (and by the test suite) instead of being read back out of the child module's resources.

Plus **`central_prerequisites`** — a map rendering the two statements the bucket owner merges (also write them into `central-prerequisites/README.md`):

**Bucket policy statement:**
```json
{
  "Sid": "AllowPatchOutcomeWritersFromOrg",
  "Effect": "Allow",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::<bucket>/patchingsolution-events/outcomes/*",
  "Condition": {
    "StringEquals": { "aws:PrincipalOrgID": "o-xxxxxxxxxx" },
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-outcome-s3-writer" }
  }
}
```

**KMS key policy statement:**
```json
{
  "Sid": "AllowPatchOutcomeWritersFromOrg",
  "Effect": "Allow",
  "Principal": "*",
  "Action": ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": { "aws:PrincipalOrgID": "o-xxxxxxxxxx" },
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-outcome-s3-writer" }
  }
}
```

Two conditions deliberately: `aws:PrincipalOrgID` bounds it to the organisation, `ArnLike` on `aws:PrincipalArn` bounds it to the one role name. Either alone is too loose.

The KMS statement is needed **only** when the bucket's default encryption is SSE-KMS with a customer-managed key; on an SSE-S3 bucket, leave `archive_kms_key_arn = null` and merge statement 1 alone. `kms:GenerateDataKey` is the action that does the work — S3 calls it on the writer's behalf for each `PutObject`; the Lambda never calls KMS directly, so the statement can optionally be pinned with `"kms:ViaService": "s3.<region>.amazonaws.com"` (drop `kms:DescribeKey` if you do).

**If the bucket has ACLs enabled** (`ObjectWriter` / `BucketOwnerPreferred` — open question 1), statement 1 is not sufficient on its own. Three coordinated changes are needed: `archive_object_acl = "bucket-owner-full-control"` in every member account, `s3:PutObjectAcl` added to the bucket-policy `Action` list with a `"s3:x-amz-acl": "bucket-owner-full-control"` condition, **and `s3:PutObjectAcl` added to the module's `S3WriteOnly` IAM statement** — a `PutObject` carrying an `x-amz-acl` header needs both permissions. The preferred fix is to switch the bucket to `BucketOwnerEnforced` and keep `archive_object_acl` null. Note that on a `BucketOwnerEnforced` bucket, sending an ACL fails the put outright with `AccessControlListNotSupported`.

`central-prerequisites/README.md` is the bucket owner's runbook for all of this: preflight commands, both statements, the Deny patterns that silently override them (`aws:SourceVpce` in particular — the writer Lambda is not in a VPC), and canary-based verification.

---

## 11. Validation the agent must run

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate      # module and example
tflint
python3 -m py_compile modules/patch-outcome-observability/src/handler.py
```

Then confirm the resource shape:

- `plan` with defaults creates **20 resources**: 4 rules, 4 targets, 4 lambda permissions, 1 function, 1 role, 1 role policy, 1 log group, 2 SQS queues, 1 queue policy, 1 invoke config
- **zero** `aws_cloudwatch_log_metric_filter` resources
- **zero** `aws_s3_bucket*` and `aws_kms_key*` resources
- `rules_enabled = false` → the three SSM rules show `DISABLED`; the canary stays `ENABLED`
- no hardcoded account IDs, bucket names, ARNs, org IDs or regions outside `examples/`
- every variable has a description; every non-trivial one has a validation block

---

## 12. Finish with a build summary

State: what was created; the resource count from `plan`; which section 9 questions remain unanswered; and any place the implementation diverged from this document, with the reason.
