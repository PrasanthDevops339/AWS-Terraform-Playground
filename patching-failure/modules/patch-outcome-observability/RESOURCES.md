# Every resource in this module, explained

Written for someone who has never seen this module (or much Terraform / AWS)
before. Read the flow first, then use the reference section to look up any one
resource.

For *why* the design is shaped this way, see `../../BUILD-INSTRUCTIONS-infrastructure.md`
and `../../HOW-IT-WORKS.md`. This file is only *what each piece does*.

---

## 1. The 30-second version

AWS patches EC2 instances by running a document called `AWS-RunPatchBaseline`.
When a patch run on an instance finishes (success **or** failure **or** "never
even attempted"), AWS emits an event. This module:

1. **Listens** for those events (EventBridge rules).
2. **Runs a small Python function** for each one (Lambda).
3. The function **writes a one-line JSON record** into a central S3 bucket
   owned by another team, which feeds Splunk.
4. If any part of that chain breaks, the message lands in a **dead-letter
   queue** (SQS) instead of vanishing.
5. A **canary** rule lets us fire a fake event on demand to prove the whole
   chain still works, even when no real patching is happening.

Everything runs **inside each member account** (there are ~450). The only
cross-account step is the final "write to the central bucket".

---

## 2. The end-to-end flow

```
                         (member account)
 AWS SSM patch run
      │  emits an event when an instance/command reaches a terminal state
      ▼
 ┌─────────────────────────────────────────────┐
 │ EventBridge (the account's "default bus")   │
 │   rule: invocation_success                  │
 │   rule: invocation_failure                  │──┐
 │   rule: command_failure                     │  │  all four point at
 │   rule: canary  (fake events, always on)    │──┤  the SAME Lambda
 └─────────────────────────────────────────────┘  │
                                                  ▼
                                   ┌──────────────────────────────┐
   EventBridge can't reach Lambda? │  Lambda: <alias>-<prefix>-    │
        message → target_dlq  ◄────┤  writer   (src/handler.py)    │
                                   │  runs with the "writer" IAM   │
                                   │  role                         │
                                   └──────────────┬───────────────┘
   Lambda ran but threw?                          │ s3:PutObject (cross-account)
        message → lambda_dlq  ◄───────────────────┤
                                                  ▼
                                   Central S3 bucket  ──►  Splunk
                                   (owned by another team;
                                    NOT created here)
```

Supporting cast that isn't on the arrow path:

- **S3 package bucket** – holds the zipped Python code so Lambda can load it.
- **CloudWatch log group** – where the Lambda's `print()` / log output goes.
- **IAM role + inline policy** – the exact set of permissions the Lambda is
  allowed to use.

---

## 3. Resource-by-resource reference

Each entry: **what it is** in AWS terms, **what it does here**, **why it
exists**, and **what breaks without it**.

### Group A — the code package (S3)

The shared Lambda module we use can only load code from an S3 bucket (not from
a local file), so we have to give it one.

---

#### `aws_s3_bucket.lambda_package`

- **What it is:** an ordinary S3 bucket, one per account, named
  `<name_prefix>-pkg-<account-id>` (e.g. `patch-outcome-pkg-111122223333`).
- **What it does here:** stores exactly one object — `handler.zip`, the zipped
  contents of `src/`.
- **Why it exists:** `terraform-aws-lambda` uploads the code to S3 and points
  the function at `s3://this-bucket/<key>`. `source_code_hash` (computed from
  the zip) tells AWS to redeploy the function whenever the code changes.
- **Without it:** the Lambda module has nowhere to put the package and the
  plan fails.
- **`force_destroy = true`:** lets `terraform destroy` delete the bucket even
  if the old package object is still in it. Safe here — the bucket holds only
  build artifacts, nothing precious.

#### `aws_s3_bucket_public_access_block.lambda_package`

- **What it is:** the switch that turns off *all four* ways an S3 bucket can
  be made public.
- **What it does here:** guarantees the code bucket can never be exposed to
  the internet, even if someone later adds a bad bucket policy or ACL.
- **Why it exists:** security baseline. Every bucket should have this; scanners
  (Wiz, checkov, trivy) flag buckets that don't.
- **Without it:** the bucket still works, but it's one misconfiguration away
  from leaking your Lambda source code publicly.

#### `aws_s3_bucket_ownership_controls.lambda_package`

- **What it is:** sets the bucket's "Object Ownership" mode to
  `BucketOwnerEnforced`.
- **What it does here:** disables S3 ACLs entirely — every object is owned by
  the bucket owner, full stop.
- **Why it exists:** ACLs are a legacy access-control mechanism that causes
  subtle "I can't read my own object" bugs. Turning them off is the modern
  default.
- **Without it:** ACLs stay enabled; usually harmless for a single-writer
  bucket, but it's the wrong default.

#### `aws_s3_bucket_server_side_encryption_configuration.lambda_package`

- **What it is:** tells S3 to encrypt every object at rest.
- **What it does here:** uses free S3-managed encryption (`AES256`) normally,
  or your member-account KMS key (`aws:kms`) if you set `local_kms_key_arn`.
  `bucket_key_enabled = true` reduces KMS API costs when a key is used.
- **Why it exists:** encryption-at-rest is a hard compliance requirement.
- **Without it:** new buckets are actually AES256-encrypted by default now, so
  the immediate effect is small — but being explicit is what passes an audit.

---

### Group B — the Lambda's log group

#### `aws_cloudwatch_log_group.this`

- **What it is:** the CloudWatch Logs "folder" a Lambda writes to, at the
  fixed path `/aws/lambda/<function-name>`.
- **What it does here:** captures everything the handler logs (each record it
  writes, every enrichment warning). Retention defaults to **365 days**
  (`lambda_log_retention_in_days`).
- **Why it exists:** if you *don't* create it, Lambda auto-creates one on first
  invocation **with retention set to "never expire"** — logs pile up forever
  and cost money. Creating it ourselves lets us set retention and (optionally)
  a KMS key.
- **Name gotcha:** the shared Lambda module prefixes the function name with
  the **account alias**, so the real function is
  `<alias>-<name_prefix>-writer` and this log group's name must match exactly
  — that's what `local.function_name` computes.
- **Without it:** logs still work, but retention is infinite and un-managed.

---

### Group C — the identity (IAM)

An IAM **role** is a "hat" the Lambda wears while running. A **policy**
attached to the role is the list of things it's allowed to do. The Lambda can
do *nothing* in AWS except what this policy grants.

#### `data.aws_iam_policy_document.assume` (not a resource — a lookup/renderer)

- **What it is:** builds a small JSON document that says "the Lambda service
  (`lambda.amazonaws.com`) is allowed to assume this role".
- **Why it exists:** every IAM role needs a "trust policy" saying *who* can
  wear it. This one says: only AWS Lambda.

#### `aws_iam_role.writer`

- **What it is:** the IAM role the Lambda runs as.
- **What it does here:** its **name is load-bearing** — it's
  `patch-outcome-s3-writer` (from `writer_role_name`), *identical in all ~450
  accounts*. The central bucket's policy grants write access to
  `arn:aws:iam::*:role/patch-outcome-s3-writer`, so the name is the join key
  between this module and the central account.
- **Why the exact name matters:** rename it in one account and that account's
  writes silently start failing with AccessDenied — the Lambda's own
  permissions still look fine, but the *central* side no longer recognises it.
- **`permissions_boundary` / `path`:** optional knobs for orgs whose SCPs
  require them.

#### `data.aws_iam_policy_document.writer` (renderer)

- **What it is:** builds the JSON for the role's permission list. Reading the
  statements top to bottom, the Lambda may:
  | Statement | Allows | Scope |
  |---|---|---|
  | `Logs` | write log lines | only its own log group |
  | `S3WriteOnly` | `s3:PutObject` | only `<central-bucket>/<prefix>/*` — nothing else, no read, no delete |
  | `KmsEncryptOnly` *(only if `archive_kms_key_arn` set)* | encrypt data with the central KMS key | that one key; **never `kms:Decrypt`** — this path only writes |
  | `LambdaDlq` | `sqs:SendMessage` | only the lambda-DLQ |
  | `SsmReadOnly` | read patch-command details for enrichment | `*` (these SSM APIs have no resource-level scoping) |
  | `Ec2DescribeForTags` *(only if `include_instance_tags` true)* | `ec2:DescribeInstances` | `*` (same reason) |
- **Why it's this tight:** least privilege. The only *write* the Lambda can do
  anywhere is one `PutObject` into one prefix.

#### `aws_iam_role_policy.writer`

- **What it is:** attaches the JSON above to the role as an **inline** policy
  (inline = lives and dies with the role, not a separately managed object).
- **Without it:** the role exists but can do nothing — every Lambda invocation
  fails with AccessDenied.

---

### Group D — the Lambda function (via `module.writer_lambda`)

#### `module.writer_lambda` → `terraform-aws-lambda`

This is a **child module** (shared code from `Terrafrom-AWS-Prasanth/`). It
creates, inside itself:

| Resource it creates | Purpose |
|---|---|
| `aws_lambda_function.main` | the function itself: Python 3.13, 128 MB, 30 s timeout, handler `handler.handler`, our 7 environment variables |
| `data.archive_file.rendered_zip` | zips up `src/` on every plan |
| `aws_s3_object.main` | uploads that zip to `aws_s3_bucket.lambda_package` |
| `aws_lambda_permission.main` (×4) | one per EventBridge rule — see below |

Key inputs we pass:

- `lambda_role_arn` = the `writer` role above.
- `environment` = tells `src/handler.py` where to write
  (`BUCKET_NAME`, `S3_PREFIX`, `KMS_KEY_ARN`), and how to behave (`ENRICH`,
  `INCLUDE_INSTANCE_TAGS`, `LOG_LEVEL`).
- `allowed_triggers` = `local.allowed_triggers`, a map with one entry per
  EventBridge rule. The module turns each entry into an
  `aws_lambda_permission`.

**Why permissions, not a role, for the trigger:** EventBridge invokes Lambda
by *pushing* to it. That requires a **resource-based policy** *on the
function* saying "EventBridge rule X may invoke me" — one statement per rule.
This is different from the execution role (Group C), which is about what the
function may do once it's running.

**Without the permissions:** the rules match events but EventBridge gets
"AccessDenied" trying to invoke the Lambda, and the event goes to
`target_dlq`.

#### `aws_lambda_function_event_invoke_config.this`

- **What it is:** settings for **asynchronous** invocations of the function
  (EventBridge invokes async).
- **What it does here:**
  - retry a failed invocation **twice** (`maximum_retry_attempts = 2`),
  - give up on events older than 6 hours (`maximum_event_age_in_seconds`),
  - on final failure, send the event to **`lambda_dlq`**
    (`on_failure` destination).
- **Why it exists:** this is the *only* thing that catches "the function ran
  and threw an exception" — e.g. the central bucket policy is wrong, or the
  KMS grant is missing. The handler deliberately does **not** catch the
  `PutObject` error, precisely so this net catches it.
- **Without it:** a function that throws just... loses the event. No record,
  no alert, nothing.

---

### Group E — the triggers (EventBridge)

EventBridge is AWS's event router. SSM patch events arrive on the account's
**default bus** and nowhere else, so all rules live there.

#### `aws_cloudwatch_event_rule.ssm` (three rules, via `for_each`)

- **What it is:** three rules — `invocation_success`, `invocation_failure`,
  `command_failure` — each with an **event pattern** (a filter).
- **What each matches:**
  | Rule | Fires when | Example `status` values |
  |---|---|---|
  | `invocation_success` | one instance finished patching cleanly | `Success` |
  | `invocation_failure` | one instance's patch run ended badly | `Failed`, `TimedOut`, `Cancelled`, `Undeliverable`, **`Terminated`** |
  | `command_failure` | the whole command (all instances) ended badly | `Failed`, `Incomplete`, `AccessDenied`, … |
- Every pattern also requires `source = aws.ssm` and a document name starting
  with `AWS-RunPatchBaseline`.
- **`state`:** `ENABLED` normally; `DISABLED` when `rules_enabled = false` —
  that's the "deploy dormant, arm later" switch. Disabled rules cost nothing
  and match nothing.
- **Why `invocation_success` is not optional:** without a "this instance
  patched fine" record, a healthy instance produces *nothing* in Splunk — and
  "nothing" is indistinguishable from "the pipeline is broken".
- **Why `Terminated` must stay in `invocation_failure`:** a `Terminated`
  instance was **never patched** (the command hit its error threshold and
  stopped). Unpatched = a failure, not a harmless skip. There's a `validation`
  block that refuses to let you remove it.

#### `aws_cloudwatch_event_target.ssm` (three targets, via `for_each`)

- **What it is:** the wiring that says "when rule X matches, send the event to
  destination Y". One per SSM rule.
- **What it does here:** destination = the writer Lambda
  (`module.writer_lambda.lambda_arn`).
- **`dead_letter_config`:** if EventBridge *cannot deliver* the event to the
  Lambda, the event goes to **`target_dlq`** instead of being dropped.
- **Without the target:** the rule matches events and then does nothing with
  them.

#### `aws_cloudwatch_event_rule.canary` *(only if `enable_canary = true`, the default)*

- **What it is:** a fourth rule that matches `source = custom.patch-canary`.
- **What it does here:** it's **always `ENABLED`**, even when the three SSM
  rules are dormant.
- **Why it exists:** you can fire a fake canary event yourself (see the
  `canary_command` output) to prove the *entire* chain works —
  rule → permission → Lambda → role → central bucket policy → KMS grant —
  without waiting for a real patch cycle. AWS rejects any `PutEvents` call
  whose source starts with `aws.`, so a canary event can never be mistaken for
  a real SSM event.
- **Without it:** with no metrics/alarms in this design, you'd have no way to
  check the pipeline is alive until real patching fails.

#### `aws_cloudwatch_event_target.canary` *(same condition)*

Same as the SSM targets: points the canary rule at the same Lambda, with the
same `target_dlq` dead-letter fallback.

---

### Group F — the safety nets (SQS dead-letter queues)

Two queues, because there are **two different ways** the pipeline can break,
and they're caught at different points.

#### `module.target_dlq` → `terraform-aws-sqs`

- **What it is:** a standalone SQS queue named `<alias>-<name_prefix>-target-dlq`.
- **Catches:** *"EventBridge could not invoke the Lambda"* — the permission
  was revoked, the function was deleted, Lambda was throttling. Attached as
  the `dead_letter_config` on **every** event target (SSM rules **and** the
  canary).
- **Retention:** 14 days (`message_retention_seconds = 1209600`).

#### `module.lambda_dlq` → `terraform-aws-sqs`

- **What it is:** a second standalone SQS queue,
  `<alias>-<name_prefix>-lambda-dlq`.
- **Catches:** *"the function ran and threw an exception"* — a bad central
  bucket policy, a missing KMS grant, an S3 error. Attached via the
  `aws_lambda_function_event_invoke_config` `on_failure` destination (Group D).
- **Retention:** 14 days.

Both queues use AWS-default **SSE-SQS** encryption (free, in-account). They
deliberately do **not** use the central KMS key — that key lives in another
account and using it here would need a cross-account grant this design avoids.

#### `data.aws_iam_policy_document.target_dlq` (renderer)

- **What it is:** builds a queue policy that lets the EventBridge service
  (`events.amazonaws.com`) call `sqs:SendMessage` on `target_dlq`.
- **Conditions:** only rules named `<name_prefix>-*` in **this** account may
  send. Prevents any other account or service dumping messages into the queue.
- **Why separate:** the shared SQS module only ships one canned policy (a
  "deny non-TLS" rule). It can't express "allow EventBridge", so we hand-write
  this one and attach it ourselves.

#### `aws_sqs_queue_policy.target_dlq`

- **What it is:** attaches the JSON above to `target_dlq`.
- **Without it:** EventBridge can't write to the queue, so the
  "EventBridge couldn't reach Lambda" failures are lost too — the safety net
  has a hole in it. (`lambda_dlq` needs no such policy; Lambda writes to it
  using the *execution role's* `LambdaDlq` permission from Group C.)

---

## 4. The data sources (lookups, not things that get created)

| Data source | What it fetches | Used for |
|---|---|---|
| `data.aws_caller_identity.current` | the 12-digit account ID | the package bucket name, the `target_dlq` policy conditions |
| `data.aws_partition.current` | `aws` (or `aws-us-gov`, `aws-cn`) | building ARNs correctly in any partition |
| `data.aws_region.current` | e.g. `us-east-1` | the `canary_command` output |
| `data.aws_iam_account_alias.current` | the account's friendly alias | the shared modules prefix every name with it, so we need it to predict the log group name |

These make **zero infrastructure changes** — they're read-only queries AWS
answers during `plan`.

---

## 5. What this module deliberately does **not** create

| Not created here | Who owns it |
|---|---|
| The central S3 bucket that records land in | another team, in the central account |
| That bucket's bucket policy | same — this module only *renders* the statement to merge, as the `central_prerequisites` output |
| The central KMS key + its key policy | same |
| Any CloudWatch alarm / metric / dashboard | nobody — detection and alerting are Splunk's job by design |
| Any SNS topic / email / Slack alerting | nobody — same reason |
| An `aws_s3_bucket_notification` on the central bucket | another team's `s3tofirehose` pipeline |

The two policy statements the central account **must** add before any of this
can write — `s3:PutObject` on the bucket, `kms:GenerateDataKey` on the key,
both scoped to the org plus the exact writer role name — are rendered by the
`central_prerequisites` output and explained step by step, with the failure
modes and the verification, in `central-prerequisites/README.md`.

---

## 6. Mini-glossary

- **EventBridge** – AWS's event bus. Things emit events; *rules* filter them;
  *targets* say where matching events go.
- **Lambda** – run code without a server. You give it a zip and a handler
  name; AWS runs it on demand.
- **Execution role** – the IAM identity a Lambda *is* while it runs. Defines
  what it can do.
- **Resource-based policy / `aws_lambda_permission`** – a rule *on the
  function* saying which other service is allowed to invoke it.
- **SQS** – a message queue. Here, used only as a dead-letter queue: a place
  failed messages land so a human can inspect them.
- **DLQ (dead-letter queue)** – the queue that catches messages that couldn't
  be processed.
- **KMS** – AWS's key-management service. "Encrypt with KMS key X" = call KMS
  to wrap the data key.
- **SSM Run Command / `AWS-RunPatchBaseline`** – the mechanism AWS uses to run
  the OS patching document on EC2 instances.
- **Partition** – `aws` for commercial regions, `aws-us-gov` for GovCloud,
  `aws-cn` for China. ARNs differ per partition.
- **`for_each` / `count`** – Terraform ways to make N copies of a resource.
  `for_each` here builds the 3 SSM rules from one block; `count` makes the
  canary 0-or-1.
- **Child module** – reusable Terraform code called with `module "x" {…}`.
  Here: `writer_lambda`, `target_dlq`, `lambda_dlq`.
