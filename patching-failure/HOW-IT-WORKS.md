# How it works

End-to-end walkthrough of what fires, in order, from an SSM patch run to a
searchable record in Splunk.

## 1. The trigger — EventBridge (default bus, every member account)

SSM emits status-change events on the account's **default** EventBridge bus
whenever a Run Command invocation or command reaches a terminal state.
Nothing needs to be configured on the SSM side — these events exist already.

`modules/patch-outcome-observability/main.tf` creates three rules that
listen for `AWS-RunPatchBaseline*` events:

| Rule | Fires on | Example |
|---|---|---|
| `invocation_success` | one instance finished successfully | instance ran the patch doc, `Success` |
| `invocation_failure` | one instance's invocation ended badly | `Failed`, `TimedOut`, `Cancelled`, `Undeliverable`, **`Terminated`** |
| `command_failure` | the whole command (not one instance) ended badly | `Failed`, `Incomplete`, `AccessDenied`, ... |

All three carry the same shape of match: `source = aws.ssm`,
`detail.document-name` prefixed `AWS-RunPatchBaseline`, `detail.status` in
the table above. Every rule targets the **same Lambda** — including the
success rule, deliberately, because a cleanly-patched instance that never
produces a record is indistinguishable in Splunk from a broken pipeline.

A fourth rule, the **canary**, matches `source = custom.patch-canary` and is
always `ENABLED` even when the other three are dormant. Nobody can forge
this from a real AWS event (EventBridge `PutEvents` rejects any source
starting with `aws.`), so firing it (see the `canary_command` output) is a
safe way to prove the whole chain — rule → permission → Lambda → role →
bucket policy → KMS grant — works, without waiting for a real patch cycle.

`rules_enabled = false` sets the three SSM rules' `state` to `DISABLED` —
EventBridge stops matching events against them (no cost, no invocations),
while the canary rule stays live. Flipping that one variable to `true` arms
the whole pipeline with no other changes.

## 2. The compute — Lambda (`src/handler.py`)

EventBridge invokes the Lambda directly (`aws_lambda_permission`, one per
rule — this is a resource policy on the function, not an IAM role, because
EventBridge→Lambda is a direct push model). The handler:

1. **Classifies the event** into one of three outcomes using
   `detail.status` and, for anything that isn't a clean `Success`, an
   enrichment call to `ssm:GetCommandInvocation` to get `StatusDetails`
   (the only place `Terminated` shows up):
   - `patched` — the document ran and returned `Success`
   - `failed` — it ran on the instance and failed
   - `not-attempted` — the instance was never touched (rate-control halted
     the command before reaching it)
2. **Builds a partitioned S3 key**:
   `outcomes/dt=<date>/<account>/<status>_<instance>_<command>_<ts>_<eventid>.json`
3. **Enriches only when there's no other record of what happened.** A
   `patched` event costs zero extra API calls — there's nothing to explain.
   A `failed` event is thin because the full error is already in Splunk
   under the stdout sourcetype, joinable on `command_id`. A
   `not-attempted` event gets `ListCommands` (target/error/completed
   counts, rate-control settings) and `DescribeInstanceInformation` (agent
   ping status) because **no stdout object was ever written for that
   instance** — this record is the only evidence it was ever in scope.
4. **Writes one JSON object per outcome** directly to the central bucket
   with `s3:PutObject`, SSE-KMS using the *central* account's key.
5. **Does not catch the `PutObject` exception.** If the bucket policy is
   wrong, the KMS grant is missing, or the bucket is unreachable, the
   Lambda throws on purpose — that's what triggers step 4 below.

See `PAYLOAD-SPEC-patch-outcome-record.md` for exact field-by-field record
shapes and sizes.

## 3. The safety net — two DLQs, because there are two different ways this can break

| Queue | Catches | How |
|---|---|---|
| `<prefix>-target-dlq` | *EventBridge couldn't even invoke the Lambda* (permission revoked, function deleted, Lambda-side throttling) | Attached as `dead_letter_config` on **every** `aws_cloudwatch_event_target`, including the canary |
| `<prefix>-lambda-dlq` | *the Lambda ran and threw* (bad bucket policy, missing KMS grant, S3 error) | Attached via `aws_lambda_function_event_invoke_config`'s `on_failure` destination |

Both are SSE-SQS encrypted (in-account, free) — not the central KMS key,
which would need a cross-account grant this module deliberately avoids.
With no CloudWatch metric/alarm tier in this design, these two queues plus
the canary are the *entire* observability into whether the pipeline itself
is healthy — everything else is observability into the *patches*, which is
Splunk's job.

## 4. The identity — one IAM role name, fleet-wide

The Lambda's execution role is named identically (`patch-outcome-s3-writer`
by default) in all ~450 accounts. That name is not incidental — it's the
join key between this Terraform module and the central account:

- **In each member account**: the role has an inline policy granting
  `s3:PutObject` on exactly `<bucket>/<prefix>/*` (nothing wider), KMS
  encrypt-only actions (never `kms:Decrypt` — this path only writes), and
  read-only SSM/EC2 describe calls for enrichment.
- **In the central account**: the bucket policy and KMS key policy (owned
  by another team, never touched by this module) grant access with a
  condition like `ArnLike aws:PrincipalArn = arn:*:iam::*:role/patch-outcome-s3-writer`
  combined with `StringEquals aws:PrincipalOrgID = o-xxxxxxxxxx`. Both
  conditions together scope the grant to "any account in this org, using
  exactly this role name" — change the role name in one account and that
  account's writes start failing with AccessDenied, silently, since the
  Lambda's own IAM in that account would still look correct.

This module renders those two statements as the `central_prerequisites`
output (and in `central-prerequisites/README.md`) for the bucket owner to
merge by hand — this module never creates or edits the bucket, the bucket
policy, or the KMS key itself.

## 5. Where it lands and how Splunk reads it

Records land under `patchingsolution-events/outcomes/`, a **sibling** of
the existing `patchingsolution/` prefix that the current stdout pipeline
uses — not a child of it, so the `s3tofirehose` labeling script (owned by
another team) doesn't mis-tag these JSON objects with the stdout
sourcetype. `s3tofirehose` picks them up and ships them into Splunk under
sourcetype `aws:ssm:patch:outcome` (parsed per `splunk/props.conf`, flat
JSON with `INDEXED_EXTRACTIONS = json`, no `FIELDALIAS` needed).

From there:
- `patch_outcome` (`patched` / `failed` / `not-attempted`) is the field ops
  pivots on.
- `command_id` is the join key back to the existing stdout sourcetype for
  the full error text on a `failed` record.
- `splunk/patch_outcome_action.csv` is a lookup table mapping
  `patch_outcome` + `status_details` → a plain-English recommended action,
  so wording changes are a CSV edit, not a redeploy across 450 Lambdas.

## The one-sentence version

EventBridge rules watch every SSM patch-command terminal state on the
default bus → push all of them (including successes) to one small Lambda →
the Lambda classifies the outcome, enriches only what stdout doesn't
already cover, and writes one JSON object to a central bucket under a
fleet-wide-identical IAM role → two DLQs plus a forgeable-proof canary are
the safety net for a system with no metrics tier → Splunk ingests the
objects next to the existing patch stdout and joins the two on
`command_id`.
