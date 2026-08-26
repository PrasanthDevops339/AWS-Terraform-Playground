# BUILD SPEC — Patch Failure Observability

**Annex A to:** `PROPOSAL-patch-failure-observability.md`
**Status:** implementation artifact. Dormant until the POC is approved at the section 8 go/no-go gate.
**Audience:** the engineer or coding agent who builds this after approval.

> This document is deliberately prescriptive and assumes the decisions in the proposal have been made. It is not the case for doing the work — that is the proposal. Read the proposal first for context, options considered, and open questions; read this only when building.

> Build only from this document. Any earlier Terraform in this repo predates a design change and is stale — do not read it, do not extend it.

---

## 0. How to use this spec

Build in this order. Run `terraform fmt`, `terraform init -backend=false` and `terraform validate` after each component. Do not proceed until the previous one validates.

1. `modules/patch-failure-observability/` — the per-account module, deployed to ~450 accounts
2. `central-prerequisites/` — policy statements the central account must apply once (not a Terraform-managed component; see section 5)
3. `athena/` and `splunk/` handoff artefacts
4. `examples/`
5. `README.md`

**Section 12 is a list of things that will look like improvements and are not.** Read it before writing code. Several are non-obvious AWS constraints that fail at apply time, or — worse — silently at 2am six months from now.

---

## 1. What this does

Detect, record and archive every failure of the `AWS-RunPatchBaseline*` SSM document across a ~450-account AWS Organizations estate.

**Environment:**

| | |
|---|---|
| Org | AWS Control Tower + Account Factory for Terraform (AFT), ~450 accounts |
| Fleet | EC2 — Amazon Linux 2, Amazon Linux 2023, RHEL, Windows Server |
| Patching | A centralised solution invokes `AWS-RunPatchBaseline` directly via Run Command |
| Notification | Splunk Observability ("Olly") scrapes CloudWatch metrics per account. **There is no SNS or SES anywhere in this org.** |
| Existing S3 path | `AWS-RunPatchBaseline` stdout already lands in `s3://<bucket>/patchingsolution/<command-id>/<instance-id>/...`, written **cross-account from all 450 accounts**. A script (`s3tofirehose`) picks it up and pushes it to Splunk with an index and sourcetype. |
| IaC | Terraform via TFE with OPA gates, GitLab CI/CD |
| Distribution | **AFT account customizations** for AFT-vended accounts; a separate StackSet or TFE workspace for management / Log Archive / Audit |

**Key operating condition: this is deployed to all accounts and sits dormant until needed.** It must cost nothing at rest and must be verifiable while idle.

---

## 2. Architecture

Everything is in-account. **There is no central event bus and no central compute.** The only shared resource is the S3 bucket that already exists.

```
MEMBER ACCOUNT  (× ~450, identical, deployed by AFT account customizations)
┌─────────────────────────────────────────────────────────────┐
│  SSM Run Command — AWS-RunPatchBaseline*                    │
│            │ terminal status event                          │
│            ▼                                                │
│  EventBridge DEFAULT bus                                    │
│    ├─ rule: invocation-failure  (has instance-id)           │
│    ├─ rule: command-failure     (never reached an instance) │
│    └─ rule: canary              (optional)                  │
│            │                                                │
│            ├──► [1] local CloudWatch log group ──► metric   │
│            │        365d forensics          filter │        │
│            │                                       ▼        │
│            │                        Custom/PatchExecution   │
│            │                              → Splunk Olly     │
│            │                                                │
│            ├──► [2] mirror into existing log group (opt)    │
│            │                                                │
│            └──► [3] Lambda ─────┐                           │
│                    │            │ EventBridge target DLQ    │
│                    │            │ Lambda failure DLQ        │
└────────────────────┼────────────┴───────────────────────────┘
                     │ PutObject, cross-account
                     ▼
   CENTRAL ACCOUNT — existing bucket, no compute
   s3://<bucket>/patchingsolution-events/failures/dt=YYYY-MM-DD/<account>/...
                     │
                     ▼   (existing pipeline, unchanged)
              s3tofirehose ──► Splunk index
```

### Why cross-account S3 rather than a central bus

The bucket **already** accepts writes from all 450 accounts, via an org-scoped `ArnLike arn:aws:iam::*:role/aftwld-*-ec2-*` statement for the AFT-vended instance profiles. Adding one more org-scoped statement for a fixed-name Lambda role reuses proven trust rather than introducing a second, parallel cross-account mechanism.

It also buys three things a central bus cannot:

- **Blast radius isolation** — one account's failure storm cannot throttle the archive for the other 449
- **Multi-region for free** — a central bus is region-bound and would need one per region; per-account Lambdas write to the same bucket from anywhere
- **No central compute at all** — the central account owns a bucket policy statement, a KMS statement and an Athena table. Nothing to operate.

### Delivery semantics — parallel fan-out, NOT failover

Each rule carries up to three targets. **EventBridge delivers to all of them simultaneously and independently.** There is no "try target 1, fall back to target 3." Nothing is conditional, nothing waits, and a failure on one target neither blocks nor triggers another.

Do not implement any conditional, ordering, or retry-chaining logic between targets. EventBridge cannot express it and it is not wanted.

| # | Target | Enabled by | Job | Failure surfaced by |
|---|---|---|---|---|
| 1 | Local CloudWatch log group | always | Feeds the metric filter → **the only alerting path**. Also in-account triage. | `AWS/Events FailedInvocations`, target DLQ |
| 2 | Mirror into an existing log group | `mirror_log_group_name` | Independent second copy | `FailedInvocations`, target DLQ |
| 3 | Lambda → cross-account S3 | `archive_bucket_name` | Archive + Splunk index; full fields in the object body **and** the object key | EventBridge target DLQ, then Lambda async failure DLQ |

These are **not interchangeable copies of one capability**:

- Target 1 is the only thing that produces a metric, and the metric is the only notification path in an org with no SNS or SES. If target 1 breaks, S3 keeps filling and nobody is told.
- Target 3 is the only thing that puts `instance-id` and `command-id` into Splunk as searchable fields.

**Target 3 does not read from the log group.** The Lambda receives the event directly from EventBridge. A broken log group, resource policy or metric filter has zero effect on the S3 record, and vice versa. That independence *is* the redundancy — not a fallback sequence.

### Three tiers, one payload

| Tier | Store | Latency | Cardinality | Job |
|---|---|---|---|---|
| **Detect** | CloudWatch metric | seconds | LOW — enforced | Splunk Olly pages a team |
| **Triage** | CloudWatch Logs, in-account | seconds | full | Logs Insights, on-call pivot |
| **Archive** | S3 → existing Splunk pipeline | ~1 s | full | index, org trend, audit |

The metric is not optional. S3 cannot alert and Athena is a minutes-latency query tool. With no SNS or SES, the CloudWatch metric is the only path to a notification.

---

## 3. The cardinality rule — the most important constraint

`instance-id`, `command-id` and `timestamp` **MUST NOT** be CloudWatch metric dimensions.

- **Timestamp cannot be a dimension at all.** It is the datapoint's own time axis.
- **Command ID is unbounded.** Every run mints a new unique metric that never repeats.
- **Instance ID is ruinously expensive.** Custom metrics bill ~$0.30/metric/month per unique dimension combination, per account:

| Dimension set | Metrics/account (~50 instances) | × 450 accounts |
|---|---|---|
| `AccountId` + `Status` | ~4 | ~$540/mo |
| `+ InstanceId` | ~200 | ~$27,000/mo |
| `+ CommandId` | unbounded | unbounded |

**All three fields are still captured in full** — in the CloudWatch log record, in the S3 object body, in the S3 object *key*, and as searchable Splunk fields. They are simply routed away from a counting system.

Encode this as a `validation` block on `metric_dimensions` (section 4.8). The guardrail belongs in the module so no downstream team can recreate the mistake.

---

## 4. The per-account module — `modules/patch-failure-observability/`

Files: `main.tf`, `archive.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `src/handler.py`, `README.md`

### 4.1 Provider constraints

```hcl
terraform {
  required_version = ">= 1.9.0"           # multiple validation blocks per variable
  required_providers {
    aws     = { source = "hashicorp/aws",      version = ">= 5.40.0, < 7.0.0" }
    archive = { source = "hashicorp/archive",  version = ">= 2.4.0" }
  }
}
```

Do **not** use `data.aws_region.current.name` — deprecated in provider 6.x, and `.region` does not exist in 5.x. Where you need the region or partition, derive them from an ARN you already own:

```hcl
locals {
  _parts          = split(":", aws_cloudwatch_log_group.this["invocation_failure"].arn)
  partition       = local._parts[1]
  region          = local._parts[3]
  logs_arn_prefix = join(":", slice(local._parts, 0, 6))   # arn:<p>:logs:<region>:<acct>:log-group
}
```

### 4.2 Log groups — three, keyed by event class

| Key | Name | Retention |
|---|---|---|
| `invocation_failure` | `${log_group_prefix}/invocation-failure` | `var.failure_retention_in_days` (365) |
| `command_failure` | `${log_group_prefix}/command-failure` | `var.failure_retention_in_days` |
| `invocation_success` | `${log_group_prefix}/invocation-success` | `var.success_retention_in_days` (30) — only when `capture_success = true` |

`log_group_prefix` default `/aws/events/patch`. Apply `var.kms_key_arn` and `var.tags`. Build with `for_each` over a `locals` map.

**They are split deliberately.** CloudWatch metric-filter JSON selectors do not reliably handle hyphenated keys (`$.detail.instance-id`), so you cannot discriminate invocation events from command events inside one shared group. Splitting keeps every selector hyphen-free.

### 4.3 EventBridge rules — two failure rules, not one

All rules go on the **default** bus. SSM service events are delivered nowhere else.

**`invocation_failure`** — per-instance result, carries `instance-id`:

```json
{
  "source": ["aws.ssm"],
  "detail-type": ["EC2 Command Invocation Status-change Notification"],
  "detail": {
    "document-name": [{ "prefix": "AWS-RunPatchBaseline" }],
    "status": ["Failed", "TimedOut", "Cancelled", "Undeliverable"]
  }
}
```

**`command_failure`** — fleet-level result, **no** `instance-id` because the run never reached an instance:

```json
{
  "source": ["aws.ssm"],
  "detail-type": ["EC2 Command Status-change Notification"],
  "detail": {
    "document-name": [{ "prefix": "AWS-RunPatchBaseline" }],
    "status": ["Failed", "TimedOut", "Cancelled", "Undeliverable",
               "Incomplete", "AccessDenied", "DeliveryTimedOut"]
  }
}
```

**`invocation_success`** — optional, `status: ["Success"]`, same detail-type as invocation_failure.

> **Why two rules.** When the SSM agent is offline, the managed instance is deregistered, or Project NAP stops the instance mid-window, an *invocation* event may never be emitted at all. The failure surfaces only at the **command** level. A single invocation-level rule silently misses exactly the failures this system exists to catch, and it is the split that lets Splunk distinguish an *environmental* failure from an *installation* failure.

Rule naming: `${var.name_prefix}-${replace(key, "_", "-")}`.
Rule state: `var.rules_enabled ? "ENABLED" : "DISABLED"` — use the `state` attribute, not the deprecated `is_enabled`.
Build patterns with `jsonencode()`, not heredocs.

### 4.4 Target 1 — local log group (primary)

```hcl
arn = aws_cloudwatch_log_group.this[each.key].arn
```

The AWS provider **strips** the `:*` suffix from `aws_cloudwatch_log_group.arn`, which is exactly the form EventBridge expects. Do not append it.

Authorisation is a **CloudWatch Logs resource policy**, not an IAM role:

- One `aws_cloudwatch_log_resource_policy`, one statement, covering all log groups
- Principal `events.amazonaws.com`; actions `logs:CreateLogStream`, `logs:PutLogEvents`
- Resources: `"${lg.arn}:*"` for each group — re-append `:*` **here**, because `PutLogEvents` is authorised at log-stream scope
- Conditions: `ArnLike aws:SourceArn` = the rule ARNs, and `StringEquals aws:SourceAccount`

> CloudWatch Logs caps resource policies at **10 per account/region** and **5120 characters**. One policy with one statement, not one per log group.

Add `depends_on = [aws_cloudwatch_log_resource_policy...]` on the targets, and a `dead_letter_config` pointing at the shared in-account DLQ (section 4.7).

### 4.5 Target 2 — mirror into an existing log group (optional)

Enabled by `var.mirror_log_group_name`. Use `data "aws_cloudwatch_log_group"` with `count` so a wrong name fails at plan time (deliberate). Add its ARN to the resource policy resource list.

**Constraint to document in the variable description: EventBridge names the log stream. You cannot choose it.** A named stream would require `aws:executeAwsApi` `PutLogEvents` inside an SSM Automation — compute this design avoids. What this gives you is *existing log group, EventBridge-managed stream*, delivered as an independent second target.

### 4.6 Target 3 — Lambda → cross-account S3

Enabled by `var.archive_bucket_name`. All resources below are `count`-gated on it.

> **Attach this target to the FAILURE rules only — never to `invocation_success`.**
>
> Stdout and stderr are already written on success and already indexed in Splunk, so archiving success events would duplicate them and add roughly 90,000 objects a month across the fleet, degrading Athena over the failure archive. The success rule exists to feed a **metric**, nothing else. Iterate the Lambda target over the failure keys only:
>
> ```hcl
> for_each = var.archive_bucket_name == null ? {} : {
>   for k, v in local.event_patterns : k => v if k != "invocation_success"
> }
> ```
>
> This asymmetry is deliberate. Do not "fix" it for consistency.

**Lambda function** `${name_prefix}-s3-writer`:

| Setting | Value |
|---|---|
| Runtime | `python3.13` |
| Handler | `handler.handler` |
| Memory | 128 MB |
| Timeout | 30 s |
| Package | `data "archive_file"` from `src/` — **no layers, no dependencies, no build step** (boto3 ships in the runtime) |
| Reserved concurrency | `var.reserved_concurrency`, default `null` (unreserved) |
| Env | `BUCKET_NAME`, `S3_PREFIX`, `KMS_KEY_ARN`, `OBJECT_ACL`, `LOG_LEVEL` |
| Log group | explicit `aws_cloudwatch_log_group` at `/aws/lambda/<fn>`, retention `var.lambda_log_retention_in_days` (default 90), so Terraform owns retention |
| VPC config | **none by default.** See section 11 question 4. |

> Leave reserved concurrency unset by default. Capping it means a bad patch night with 500 simultaneous failures throttles, retries, and eventually dead-letters the very events you most wanted.

**Execution role — the name is load-bearing:**

```hcl
name = var.writer_role_name   # default "patch-failure-obs-s3-writer"
path = var.iam_role_path
```

This name **must be identical in every account**, because the central bucket and KMS policies authorise it with `ArnLike arn:<p>:iam::*:role/<name>`. Do not derive it from `name_prefix`, do not append a suffix, do not let Terraform randomise it. Add a variable validation rejecting anything containing `*` or `/`.

> This is the opposite situation to the AFT-vended instance profiles, which carry generated suffixes and *forced* the wildcard. Here you control the name, so pin it.

Inline policy, least privilege:

- `logs:CreateLogStream`, `logs:PutLogEvents` on its own log group only
- `s3:PutObject` on `arn:<p>:s3:::<bucket>/<prefix>/*` — nothing wider, no `s3:*`, no bucket-level actions
- `kms:GenerateDataKey`, `kms:Encrypt`, `kms:DescribeKey` on `var.archive_kms_key_arn` when supplied
- `sqs:SendMessage` on the Lambda failure DLQ

Support `var.permissions_boundary_arn`.

**EventBridge → Lambda** uses `aws_lambda_permission` (`principal = "events.amazonaws.com"`, `source_arn` = the rule ARN), one per rule. Not a role.

**Async failure destination:**

```hcl
resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this[0].function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600
  destination_config {
    on_failure { destination = aws_sqs_queue.lambda_dlq[0].arn }
  }
}
```

### 4.7 Two DLQs — different failure points, both required

| Queue | Catches | Attached to |
|---|---|---|
| `${name_prefix}-target-dlq` | *"EventBridge could not invoke the target at all"* — permissions revoked, function deleted, log group gone | `dead_letter_config` on every `aws_cloudwatch_event_target` |
| `${name_prefix}-lambda-dlq` | *"the function ran and threw"* — bucket policy, KMS grant, S3 error | `aws_lambda_function_event_invoke_config` `on_failure` |

Both: 14-day retention, `kms_master_key_id` when a CMK is supplied else `sqs_managed_sse_enabled = true`.

Target DLQ queue policy allows `events.amazonaws.com` to `sqs:SendMessage` with `ArnLike aws:SourceArn = arn:<partition>:events:*:<account>:rule/${name_prefix}-*`.

The handler **re-raises on error** so the second queue actually engages.

### 4.8 Metric filters — the only thing touching CloudWatch Metrics

One per log group.

```hcl
pattern = "{ $.source = \"aws.ssm\" }"
```

`$.source` is used because it is hyphen-free and always present. The EventBridge rule already did the filtering; this pattern just needs to match everything in the group.

```hcl
metric_transformation {
  name       = local.metric_names[each.key]   # PatchInvocationFailed / PatchCommandFailed / PatchInvocationSucceeded
  namespace  = var.metric_namespace           # default "Custom/PatchExecution"
  value      = "1"
  unit       = "Count"
  dimensions = var.metric_dimensions          # default { AccountId = "$.account", Status = "$.detail.status" }
}
```

**Omit `default_value`.** The CloudWatch API rejects `defaultValue` when `dimensions` is set. Document the consequence in a comment: zero failures emits **no datapoint**, not a `0`. Splunk and any CloudWatch alarm must treat missing data as healthy for the failure metrics.

**Required validation blocks on `metric_dimensions`:**

```hcl
validation {                                    # 1 — hard API limit
  condition     = length(var.metric_dimensions) >= 1 && length(var.metric_dimensions) <= 3
  error_message = "CloudWatch metric filters support between 1 and 3 dimensions."
}

validation {                                    # 2 — the cardinality guardrail
  condition = alltrue([
    for v in values(var.metric_dimensions) :
    !can(regex("(instance-id|command-id|instance_id|command_id|[$][.]id|[$][.]time|[$][.]resources|[$][.]detail[.]requested)", v))
  ])
  error_message = "High-cardinality selector rejected. See section 3 of the build spec. These fields ARE captured in the log record, the S3 object body and the S3 object key."
}

validation {                                    # 3 — selectors only
  condition     = alltrue([for v in values(var.metric_dimensions) : startswith(v, "$.")])
  error_message = "Dimension values must be CloudWatch Logs JSON selectors starting with '$.'. Static strings are not supported."
}
```

### 4.9 `src/handler.py`

```python
"""
Writes one EventBridge patch-failure event to the central S3 bucket as a single
JSON object. Runs in every member account; writes cross-account.

The object key carries account, status, instance-id, command-id and timestamp so
a plain `aws s3 ls` prefix listing is enough to find a specific failure -- no
Athena, no Splunk, no console.

The EventBridge event id is in the key, which makes at-least-once delivery
idempotent: a retry overwrites the same object rather than duplicating it.
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.config import Config

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

S3 = boto3.client("s3", config=Config(retries={"max_attempts": 5, "mode": "adaptive"}))

BUCKET = os.environ["BUCKET_NAME"]
PREFIX = os.environ["S3_PREFIX"].strip("/")
KMS_KEY_ARN = os.environ.get("KMS_KEY_ARN") or None
# Required only when the bucket has ACLs ENABLED (ObjectWriter /
# BucketOwnerPreferred). Without it the writing account owns the object and the
# bucket owner cannot read it. Empty when the bucket is BucketOwnerEnforced.
OBJECT_ACL = os.environ.get("OBJECT_ACL") or None


def _safe(value, default="unknown", limit=128):
    """S3-key-safe token. Never let an event field inject a path separator."""
    if not value:
        return default
    cleaned = "".join(c if (c.isalnum() or c in "-_.") else "-" for c in str(value))
    return cleaned[:limit] or default


def _build_key(event):
    detail = event.get("detail") or {}
    ts = event.get("time") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    day = ts[:10]                                   # YYYY-MM-DD, the dt= partition
    compact = ts.replace("-", "").replace(":", "")  # 20260825T021407Z

    return (
        f"{PREFIX}/dt={day}/{_safe(event.get('account'))}/"
        f"{_safe(detail.get('status'))}_"
        f"{_safe(detail.get('instance-id'), 'no-instance')}_"
        f"{_safe(detail.get('command-id'), 'no-command')}_"
        f"{compact}_{_safe(event.get('id'))}.json"
    )


def handler(event, context):
    key = _build_key(event)

    args = {
        "Bucket": BUCKET,
        "Key": key,
        # Trailing newline: NDJSON-compatible for any downstream consumer.
        "Body": (json.dumps(event, separators=(",", ":")) + "\n").encode("utf-8"),
        "ContentType": "application/json",
    }
    if KMS_KEY_ARN:
        args["ServerSideEncryption"] = "aws:kms"
        args["SSEKMSKeyId"] = KMS_KEY_ARN
    if OBJECT_ACL:
        args["ACL"] = OBJECT_ACL

    # Deliberately NOT wrapped in try/except. An exception here is how the
    # Lambda async failure destination gets exercised -- swallowing it would
    # make a broken bucket policy or revoked KMS grant invisible.
    S3.put_object(**args)

    LOG.info(
        "archived patch failure",
        extra={"s3_key": key, "event_id": event.get("id"), "account": event.get("account")},
    )
    return {"bucket": BUCKET, "key": key}
```

**Resulting object key:**

```
patchingsolution-events/failures/dt=2026-08-25/111122223333/Failed_i-0abc123_3f2c8d91_20260825T021407Z_a1b2c3d4.json
                                  └partition─┘ └─account──┘ └stat┘ └instance┘ └command┘ └─timestamp──┘ └event-id┘
```

Command-level failures render `no-instance` in the instance slot. That is a feature — they are visually distinct in a prefix listing.

### 4.10 The S3 prefix decision

**Default `archive_s3_prefix` = `patchingsolution-events/failures`** — a **sibling** of the existing `patchingsolution/` prefix, not a child.

This is deliberate. If `s3tofirehose` matches on the `patchingsolution/` prefix, dropping event JSON inside it means the labeling script tags these records with the RunPatchBaseline **stdout** sourcetype. They parse as garbage into the wrong index — which looks like success from the AWS side and is far worse than the events never arriving.

Encode the full rationale in the variable description, including the questions in section 11.

### 4.11 Dormancy canary (optional)

Enabled by `var.enable_canary`, meaningful only when the archive path is on.

A parallel rule matching `{"source": ["custom.patch-canary"]}` targeting the same Lambda. **You cannot spoof `aws.ssm`** — `PutEvents` rejects any source beginning with `aws.` — so the canary proves the plumbing (Lambda, execution role, bucket policy, KMS grant), not the SSM event pattern.

Fired from the existing weekly pipeline, in any account:

```bash
aws events put-events --entries '[{
  "Source":"custom.patch-canary",
  "DetailType":"Patch Failure Archive Canary",
  "Detail":"{\"status\":\"Canary\",\"emitted\":\"pipeline\"}"}]'
```

### 4.12 Variables

| Variable | Type | Default | Notes |
|---|---|---|---|
| `name_prefix` | string | `patch-failure-obs` | regex `^[a-z0-9][a-z0-9-]{2,40}$` |
| `log_group_prefix` | string | `/aws/events/patch` | |
| `patch_document_name_prefix` | string | `AWS-RunPatchBaseline` | prefix match catches `...Association` too |
| `invocation_failure_statuses` | list(string) | `["Failed","TimedOut","Cancelled","Undeliverable"]` | validate it does not contain `Success` |
| `command_failure_statuses` | list(string) | see 4.3 | |
| `capture_success` | bool | `false` | Emits a success **metric** only. The success rule must NOT reach the Lambda/S3 target — see 4.6. |
| `rules_enabled` | bool | `true` | `false` = deploy dormant |
| `metric_namespace` | string | `Custom/PatchExecution` | reject `AWS/` prefix |
| `metric_name_invocation_failure` | string | `PatchInvocationFailed` | |
| `metric_name_command_failure` | string | `PatchCommandFailed` | |
| `metric_name_invocation_success` | string | `PatchInvocationSucceeded` | |
| `metric_dimensions` | map(string) | `{AccountId="$.account", Status="$.detail.status"}` | 3 validations, section 4.8 |
| `failure_retention_in_days` | number | `365` | validate against the CloudWatch allowed list |
| `success_retention_in_days` | number | `30` | same list |
| `kms_key_arn` | string | `null` | local log groups + SQS |
| `mirror_log_group_name` | string | `null` | |
| **`archive_bucket_name`** | string | `null` | existing central bucket. `null` disables the whole Lambda path. |
| **`archive_s3_prefix`** | string | `patchingsolution-events/failures` | reject leading/trailing `/` |
| **`archive_kms_key_arn`** | string | `null` | the **central** CMK protecting the bucket |
| **`archive_object_acl`** | string | `null` | set `bucket-owner-full-control` only when the bucket has ACLs enabled. Section 11 q1. |
| **`writer_role_name`** | string | `patch-failure-obs-s3-writer` | **must be identical fleet-wide.** Reject `*` and `/`. |
| `reserved_concurrency` | number | `null` | |
| `lambda_log_retention_in_days` | number | `90` | |
| `enable_canary` | bool | `false` | |
| `iam_role_path` | string | `/` | |
| `permissions_boundary_arn` | string | `null` | |
| `tags` | map(string) | `{}` | |

Allowed retention values: `1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1096,1827,2192,2557,2922,3288,3653`

### 4.13 Outputs

`metric_namespace`, `metric_names`, `metric_dimensions`, `log_group_names`, `log_group_arns`, `event_rule_arns`, `event_patterns`, `writer_role_arn`, `lambda_function_arn`, `target_dlq_url`, `lambda_dlq_url`, `mirror_log_group_arn`, `archive_s3_destination`.

Plus these, which exist to be pasted into runbooks and dashboards:

**`logs_insights_query`** — Logs Insights requires backticks for hyphenated JSON keys:

```
fields @timestamp, account as account_id, region as aws_region,
       detail.status as status,
       detail.`instance-id` as instance_id,
       detail.`command-id` as command_id,
       detail.`document-name` as document_name,
       detail.`requested-date-time` as requested_at
| sort @timestamp desc
| limit 200
```

**`logs_insights_query_top_offenders`** — `stats count(*) by instance_id, status`, sorted descending.

**`health_metrics_to_watch`** — a map naming the free AWS-native metrics that prove a dormant deployment still works:

| Metric | Namespace | Means |
|---|---|---|
| `FailedInvocations` | `AWS/Events` | a target is broken |
| `TriggeredRules` | `AWS/Events` | events are matching at all |
| `Errors` | `AWS/Lambda` | the writer ran and threw |
| `ApproximateNumberOfMessagesVisible` | `AWS/SQS` | either DLQ has caught something |

**`central_prerequisites`** — renders the exact bucket-policy and KMS-key-policy statements the central account must apply (section 5). Rendering them as an output means the module never touches the central account.

---

## 5. Central prerequisites — apply once, by hand or by the bucket owner's own IaC

**Do not create `aws_s3_bucket`, `aws_s3_bucket_policy`, or `aws_kms_key_policy` anywhere in this repo.** The bucket exists and its policy already carries the org-scoped statement for the AFT-vended instance profiles. A Terraform-owned policy resource would replace it and break patch logging for every account.

Emit these as an output and as a `central-prerequisites/README.md`.

### 5.1 Bucket policy statement to MERGE

```json
{
  "Sid": "AllowPatchFailureWritersFromOrg",
  "Effect": "Allow",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::<bucket>/patchingsolution-events/failures/*",
  "Condition": {
    "StringEquals": { "aws:PrincipalOrgID": "o-xxxxxxxxxx" },
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-failure-obs-s3-writer" }
  }
}
```

Two conditions, deliberately. `aws:PrincipalOrgID` bounds it to the organisation; `ArnLike` on `aws:PrincipalArn` bounds it to the one role name. Either alone is too loose.

Scoped to `s3:PutObject` on the failures prefix only — no bucket-level actions, no wildcard on the object path.

If the bucket enforces SSE-KMS, add `"StringEquals": {"s3:x-amz-server-side-encryption": "aws:kms"}`.

### 5.2 KMS key policy statement to MERGE

Cross-account KMS requires **both** the key policy and the caller's IAM policy to allow the action. The IAM half is in the Lambda role (4.6); this is the other half.

```json
{
  "Sid": "AllowPatchFailureWritersFromOrg",
  "Effect": "Allow",
  "Principal": "*",
  "Action": ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": { "aws:PrincipalOrgID": "o-xxxxxxxxxx" },
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-failure-obs-s3-writer" }
  }
}
```

No `kms:Decrypt` — this path only ever writes.

### 5.3 Object ownership — verify before deploying

| Bucket setting | What the Lambda must do |
|---|---|
| `BucketOwnerEnforced` (ACLs disabled) | nothing — ownership transfers automatically. Leave `archive_object_acl = null`. |
| `ObjectWriter` / `BucketOwnerPreferred` | set `archive_object_acl = "bucket-owner-full-control"`, **and** add `"StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}` to the bucket policy condition |

Get this wrong with ACLs enabled and the objects are owned by the writing account. The bucket owner cannot read its own bucket, `s3tofirehose` sees nothing, and every `PutObject` returns 200. This is the single highest-risk item in the build.

---

## 6. Splunk artefacts — `splunk/props.conf` and `splunk/searches.spl`

The high-value capability: `AWS-RunPatchBaseline` writes stdout to `patchingsolution/<command-id>/<instance-id>/...`, so **the command ID is in the object path**. Once the failure event is indexed with `command_id` as a field, it joins natively to the stdout you already index. One search goes from "a failure fired at 02:14 in account X" to the actual yum or Windows Update error text.

```ini
[aws:ssm:patch:failure]
INDEXED_EXTRACTIONS = json
KV_MODE             = none
SHOULD_LINEMERGE    = false
LINE_BREAKER        = ([\r\n]+)
TRUNCATE            = 10000

# Index on EVENT time, not ingestion time. Otherwise every failure appears to
# have happened when Splunk saw it and hour-of-day correlation is meaningless.
TIMESTAMP_FIELDS        = time
TIME_FORMAT             = %Y-%m-%dT%H:%M:%SZ
MAX_TIMESTAMP_LOOKAHEAD = 32

FIELDALIAS-patch_ids = "detail.instance-id" AS instance_id \
                       "detail.command-id" AS command_id \
                       "detail.document-name" AS document_name \
                       "detail.status" AS patch_status
EVAL-account_id    = account
EVAL-failure_class = if(match('detail-type', "Invocation"), "installation", "environmental")
```

Generate `splunk/searches.spl` with: the stdout join on `command_id`; the **divergence search** — events reporting `Success` with no corresponding stdout object for that command ID, which detects silent S3 log-upload failures and is the highest-value search here; fleet failure rollup; chronic offenders (`dc(day) >= 3` over 90d); environmental-vs-installation timechart; suspected NAP collisions (environmental failures clustered by hour); and a **canary heartbeat** search alerting when no canary has arrived in 8 days.

> The canary heartbeat is the only search that fires when *nothing* happens — the failure mode that matters for a dormant deployment.

---

## 7. Athena — `athena/patch_failures.sql`

External table over the archive with **partition projection** (no crawler, no `MSCK REPAIR`, nothing to maintain while dormant):

```
LOCATION 's3://<bucket>/patchingsolution-events/failures/'
'projection.enabled'        = 'true'
'projection.dt.type'        = 'date'
'projection.dt.format'      = 'yyyy-MM-dd'
'projection.dt.range'       = '2026-01-01,NOW'
'projection.dt.interval'    = '1'
'projection.dt.unit'        = 'DAYS'
'storage.location.template' = 's3://<bucket>/patchingsolution-events/failures/dt=${dt}/'
```

`dt` is the **only** partition key. The account-id directory beneath it is read recursively — do not make it a second partition; dynamic partitioning costs more and buys nothing at failure volume.

Include the same analysis queries as the Splunk searches, plus a comment on the "accounts that reported nothing in 90 days" query explaining that silence is ambiguous (section 10).

---

## 8. Examples — `examples/`

**`examples/aft-account-customizations/`** — the fleet pattern. Source the module by git tag, wire `archive_bucket_name`, `archive_kms_key_arn` and `writer_role_name`, and comment that non-AFT accounts (management, Log Archive, Audit) need a StackSet or a dedicated TFE workspace.

**`examples/minimal/`** — Logs + metrics only, `archive_bucket_name = null`. Proves the module degrades cleanly with the archive path disabled.

---

## 9. Cost model — state this in the README

**At rest: $0.**

- EventBridge rules matching AWS service events on the default bus — free
- Empty log groups — free
- Metric filters that never fire — no metric exists, nothing billed
- Empty SQS queues — free
- Lambda with no invocations — free

**When firing:** ~4 metrics/account ≈ $1.20/account/month ≈ **$540/month across 450 accounts**, plus negligible Lambda, S3 and cross-region transfer.

Cost was never the constraint on Lambda — it is free at this volume. The constraint that shaped this design is metric cardinality (section 3).

---

## 10. Known limitation — document prominently

**Silence is ambiguous.** Every tier reports *failures*. None can distinguish:

- "patching is healthy"
- "patching never ran"
- "the writer rotted three months ago"

Three different situations, one identical signal: nothing.

Closing this needs a **denominator**. `capture_success = true` gives per-invocation success counts; joining that against the account and instance inventory turns "no failures" into either "N of N patched" or "N of M patched, here are the missing". Out of scope for this build, but it must be named in the README — retrofitting a denominator across 450 accounts is a second rollout.

The canary heartbeat (4.11) partially covers the third case: it proves the pipeline is alive, not that patching ran.

---

## 11. Open questions — do NOT guess, surface these

Put these in the README under "Before you deploy" and flag them in the build summary.

1. **What is the bucket's Object Ownership setting?** `BucketOwnerEnforced`, or ACLs enabled? This decides `archive_object_acl` and is the highest-risk unknown in the build. Section 5.3.
2. **Does the existing bucket policy contain an explicit `Deny`** that would catch the writer role? Some central logging buckets carry deny-unless-in-this-list statements that swallow writes while returning success upstream.
3. **Do SCPs or permissions boundaries restrict `lambda:CreateFunction`,** mandate a boundary, or require specific role paths?
4. **Is Lambda forced into a VPC by policy?** If so it needs an S3 gateway endpoint and a KMS interface endpoint, or every invocation hangs until timeout. The module defaults to no VPC config.
5. **How does `s3tofirehose` discover new objects** — S3 event notifications, EventBridge S3 notifications, or a scheduled scan?
6. **Is that discovery rule prefix-scoped, and would it cover `patchingsolution-events/`?**
7. **If it uses `aws_s3_bucket_notification`** — that resource is authoritative for the entire bucket. Adding a second one silently wipes the existing configuration and breaks ingestion for every account. Use EventBridge S3 notifications (bucket-level, additive) or have the owning team add the prefix to *their* resource.
8. **Confirm a NEW Splunk sourcetype.** Do not reuse the stdout sourcetype.
9. **Does `source` carry the S3 object key** in the existing Splunk pipeline, or is it `s3_key` / metadata? The stdout-join search depends on it.
10. **Is patching single-region?** The design supports multi-region natively, but the bucket, CMK and Athena table are single-location — confirm cross-region write cost and latency are acceptable.

---

## 12. MUST NOT — read before writing code

These will look like improvements. They are not.

| Do not | Why |
|---|---|
| Add `instance-id`, `command-id` or timestamp as metric dimensions | ~$27,000/mo, unbounded, and timestamp cannot be a dimension at all. Section 3. |
| Create an `aws_cloudwatch_namespace` resource | It does not exist. A namespace materialises on first `PutMetricData`. |
| Introduce a custom or central event bus | Explicitly rejected. Everything is in-account; the only cross-account hop is `PutObject`. |
| Put the SSM rules on anything but the default bus | AWS service events are delivered to the default bus only. |
| Set `default_value` alongside `dimensions` on a metric filter | The CloudWatch API rejects it. |
| Use hyphenated JSON selectors (`$.detail.instance-id`) in metric filters | Unreliable. Logs Insights supports them via backticks; metric filters do not. |
| Append `:*` to `aws_cloudwatch_log_group.arn` for an EventBridge target | The provider already strips it; EventBridge wants the stripped form. Re-append **only** in the resource policy. |
| Use `data.aws_region.current.name` | Deprecated in provider 6.x, absent as `.region` in 5.x. Derive from an ARN. Section 4.1. |
| Derive, randomise or suffix `writer_role_name` | The central bucket and KMS policies match it with `ArnLike ...:role/<exact-name>`. It must be identical in all 450 accounts. |
| Create `aws_s3_bucket`, `aws_s3_bucket_policy` or `aws_kms_key_policy` | The bucket exists and its policy carries the AFT `ArnLike` statement. Render statements to merge; never own the policy. |
| Create an `aws_s3_bucket_notification` | Authoritative per bucket. A second one silently wipes the existing config. |
| Grant the writer role `s3:*` or bucket-level actions | `s3:PutObject` on the failures prefix, nothing else. |
| Add `kms:Decrypt` to the writer role or key statement | This path only writes. |
| Wrap the Lambda `put_object` in try/except | Swallowing the exception disables the async failure destination and hides a broken bucket policy or KMS grant. |
| Implement the three targets as a conditional failover chain | EventBridge fans out in parallel and cannot express "try A, else B". Section 2. |
| Make the Lambda path read from the CloudWatch log group | It is fed directly by EventBridge. Coupling them destroys the independence that makes this redundant. |
| Add SNS, SES, or email | This org has none. Splunk Olly owns notification. |
| Use Firehose | Rejected: opaque object keys, minutes of buffering, and no control over the format `s3tofirehose` consumes. |
| Add a Lambda layer, `requirements.txt`, or a build step | boto3 ships in the runtime. Zero dependencies is the design. |
| Set reserved concurrency by default | Throttles exactly when a bad patch night generates the most events. |
| Drop the CloudWatch metric because S3 reaches Splunk | S3 cannot alert; Athena is minutes. With no SNS/SES the metric is the only notification path. |
| Attach the Lambda/S3 target to the `invocation_success` rule | Stdout is already written on success and already in Splunk. Archiving success events duplicates it and adds ~90k objects/month fleet-wide. Success feeds a metric only. Section 4.6. |
| Merge the two failure rules into one | The command-level rule catches runs that never reached an instance — the NAP/agent-offline case. Section 4.3. |

---

## 13. Acceptance criteria

**Static**

- [ ] `terraform fmt -check -recursive` clean
- [ ] `terraform validate` clean in the module and both examples
- [ ] `tflint` clean; `python -m py_compile src/handler.py` clean
- [ ] Every variable has a description; every non-trivial one has validation
- [ ] No hardcoded account IDs, bucket names, ARNs, org IDs or regions outside `examples/`
- [ ] `plan` with `archive_bucket_name = null` creates only: 2 log groups, 2 rules, 2 targets, 1 resource policy, 2 metric filters, 1 target DLQ — **no Lambda, no writer role**
- [ ] `plan` with the archive enabled adds exactly: 1 Lambda, 1 role + policy, 1 Lambda log group, 1 Lambda DLQ, 2 lambda permissions, 2 more targets, 1 invoke config

**Functional — in one non-prod account**

- [ ] Paste a sample `EC2 Command Invocation Status-change Notification` into the EventBridge console Sandbox; confirm it matches the invocation rule and does **not** match the command rule
- [ ] Force a real failure (stop an instance mid-run, or target a box with the agent stopped); confirm records appear in **all three tiers**
- [ ] Confirm the metric appears in `Custom/PatchExecution` with exactly `AccountId` and `Status` — **and no other dimensions**
- [ ] Confirm the S3 object key contains account, status, instance-id, command-id and timestamp
- [ ] Confirm the object body is valid JSON with a trailing newline
- [ ] **From the CENTRAL account, `aws s3 cp` the object down.** This is the object-ownership check — if it fails with AccessDenied, section 5.3 is wrong for your bucket.
- [ ] With `capture_success = true`, confirm success events emit a metric and produce **no** object in the S3 archive prefix
- [ ] Fire the canary; confirm an object lands within ~5 seconds
- [ ] Run both Logs Insights queries; confirm `instance_id` and `command_id` resolve
- [ ] Create the Athena table; confirm partition projection returns the canary rows with no `MSCK REPAIR`

**Chaos — prove the dormancy safety net**

- [ ] Remove the bucket policy statement, fire the canary, confirm the **Lambda DLQ** depth rises, `AWS/Lambda Errors` ticks, and the function logs the AccessDenied
- [ ] Remove the KMS key policy statement, fire the canary, confirm the same
- [ ] Delete the `aws_lambda_permission`, fire the canary, confirm the **target DLQ** depth rises and `AWS/Events FailedInvocations` ticks
- [ ] Restore all three; confirm recovery with no manual replay beyond draining the DLQs

**Dormancy**

- [ ] Set `rules_enabled = false`; confirm every rule shows `DISABLED` and nothing fires
- [ ] Confirm the account's CloudWatch bill for the namespace is $0 while dormant
- [ ] Enable TFE drift detection on these workspaces — dormant infrastructure is exactly what gets "cleaned up" by someone doing housekeeping

---

## 14. Deliverables checklist

```
modules/patch-failure-observability/
    main.tf  archive.tf  variables.tf  outputs.tf  versions.tf  README.md
    src/handler.py
central-prerequisites/README.md      # bucket policy + KMS statements, object-ownership decision
examples/aft-account-customizations/main.tf
examples/minimal/main.tf
athena/patch_failures.sql
splunk/props.conf
splunk/searches.spl
README.md            # architecture, cost model, section 10 limitation, section 11 questions
```

Finish with a build summary listing: what was created, which section 11 questions remain unanswered, and any place the implementation diverged from this spec and why.
