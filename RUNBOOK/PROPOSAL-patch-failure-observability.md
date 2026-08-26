# Patch Failure Observability — Research, Spike & POC Proposal

**Capability:** In-Place Patching Baseline Standardization, Reliability, and Observability
**Author:** Cloud Platform Engineering
**Status:** Proposal — seeking approval to spike
**Decision requested:** ~3 weeks of one engineer's time, plus inputs from four teams (section 11)

---

## 1. Executive summary

`AWS-RunPatchBaseline` fails for dozens of unrelated reasons — repository unreachable, package manager lock, disk full, SSM agent offline, instance stopped mid-window by Project NAP, S3 log upload denied. Today, across ~450 accounts, we have no consistent way to know that a patch run failed, on which instance, or why. Failures are discovered by absence: someone notices a compliance report looks wrong, weeks later.

Enumerating every failure reason in script logic is not achievable and not maintainable. **This proposal takes the opposite approach: react to the terminal state of the patch execution and capture the reason as evidence, rather than trying to predict causes.**

The proposed design is event-driven, deployed dormant across the fleet via AFT account customizations, and costs **nothing while idle**. It reuses three things we already operate — the CloudWatch metrics that Splunk Observability scrapes, the central S3 bucket that already receives patch logs cross-account from every account, and the stdout/stderr already indexed in Splunk. That third asset matters more than it first appears: because the SSM event and the command output share a join key, holding both lets us detect runs that report success while their own log upload failed silently — a blind spot that is invisible today (section 3.6). It introduces no new central component, no SNS/SES (we have neither), and no new cross-account trust mechanism.

We are asking for a **timeboxed spike to resolve ten open questions** (four of which are blocking), followed by a **POC in two non-production accounts** with defined go/no-go criteria. Estimated total: **3 weeks, one engineer**.

**Recurring cost at full fleet scale: ~$540/month.** The alternative design most teams reach for first would cost ~$27,000/month for the same information — section 4.2 explains why.

---

## 2. Problem statement

### 2.1 What the capability requires

The In-Place Patching capability document states these acceptance criteria, none of which we currently meet:

| Requirement | Current state |
|---|---|
| All patch failures must generate actionable events | No events generated; failures found by inspection |
| Event-driven detection | None — we rely on compliance snapshots, which lag |
| Failure notifications to Cloud Operations | No path exists |
| Logs must include execution status and instance-level results | Stdout lands in S3 but nothing flags failure |
| Track failures to resolution | No record to track |
| Identify recurring issues | Not possible without a queryable history |
| Detect instances not included in patch runs | Not possible |
| Differentiate operational/environmental failures from patch installation failures | Not possible |

### 2.2 Why the obvious approach does not work

The instinct is to wrap the patch invocation in a script that handles failures. **We cannot.** The centralised patching solution owns the `AWS-RunPatchBaseline` invocation directly — there is no interception point. Any solution must be *reactive*, observing the outcome rather than controlling the execution.

The second instinct is to script per-failure-reason handling. **We should not.** The failure surface is open-ended and grows with every OS, package manager and repository change. Every unhandled reason becomes a silent gap.

### 2.3 Constraints we are designing within

| Constraint | Implication |
|---|---|
| No SNS, SES, or email infrastructure anywhere in the org | Notification must go via CloudWatch metrics → Splunk Olly |
| Splunk Olly scrapes CloudWatch per account and owns per-team routing | Reuse it; do not build a parallel notification path |
| ~450 AFT-vended accounts | Anything per-account must be zero-touch and zero-maintenance |
| Central S3 bucket already receives patch logs cross-account from all accounts | A proven trust path exists — reuse rather than duplicate |
| `s3tofirehose` already labels S3 content and pushes it to Splunk with index + sourcetype | Ingestion is solved; we need to land data in the right shape |
| Solution will sit dormant between incidents | Must cost nothing at rest **and** be verifiable while idle |

---

## 3. Research findings

These were established during design investigation. Several are non-obvious and materially changed the architecture. They are recorded here because they will otherwise be rediscovered — expensively — by whoever builds this.

### 3.1 AWS platform constraints

| Finding | Consequence for the design |
|---|---|
| **EventBridge has no S3 target.** There is no `PutObject` target type. | Landing events in S3 requires either Firehose or Lambda in between. |
| **A CloudWatch metric namespace is not a resource.** There is no `aws_cloudwatch_namespace`; it materialises on first `PutMetricData` and disappears when data ages out. | Terraform creates the *publisher*, never the namespace. Any plan expecting to "create a namespace" is wrong. |
| **AWS service events reach the default event bus only.** SSM events cannot be routed to a custom bus. | Rules must sit on the default bus. (A rule *may* forward to a custom bus — a different mechanism.) |
| **CloudWatch metric filters reject `defaultValue` when `dimensions` are set.** | "Zero failures" emits **no datapoint**, not a `0`. Splunk and any alarm must treat missing data as healthy. |
| **Metric-filter JSON selectors do not reliably handle hyphenated keys** (`$.detail.instance-id`). Logs Insights supports them via backticks; metric filters do not. | Forced the split into separate log groups per event class. |
| **CloudWatch Logs caps resource policies at 10 per account/region, 5120 characters.** | One policy with one wildcard statement, not one per log group. |
| **`PutEvents` rejects any source beginning with `aws.`** | A synthetic canary cannot impersonate a real SSM event; it must run as a parallel rule on a custom source. |
| **Cross-account S3 writes with ACLs enabled leave objects owned by the writing account.** Every `PutObject` returns 200; the bucket owner then gets AccessDenied reading its own bucket. | Highest-risk unknown in the build. Spike question S1. |

### 3.2 The cardinality finding — the most consequential result

The natural design is to publish a CloudWatch metric carrying instance ID, command ID, account ID and timestamp. **This is not viable.**

- **Timestamp cannot be a dimension at all** — it is the datapoint's own time axis.
- **Command ID is unbounded** — every run mints a unique metric that never repeats. It cannot be charted or alarmed on, and the count grows forever.
- **Instance ID is ruinously expensive.** Custom metrics bill ~$0.30/month per unique dimension combination, per account:

| Dimension set | Metrics/account (~50 instances) | ×450 accounts, annualised |
|---|---|---|
| `AccountId` + `Status` | ~4 | **~$6,500/yr** |
| `+ InstanceId` | ~200 | **~$324,000/yr** |
| `+ CommandId` | unbounded | unbounded |

**The resolution: metrics for counting, logs for identifying.** The count of failures is low-cardinality and belongs in CloudWatch, where it triggers Splunk Olly. The instance/command/timestamp tuple is a forensic record and belongs in the log and the archived object — where Splunk indexes it as a searchable field at no marginal cost.

Nothing is lost. All three fields are captured in full, in three places. They are simply routed away from a counting system.

> **Recommendation:** encode this as a Terraform variable validation *and* an OPA policy at plan time, so the mistake becomes unmakeable rather than merely documented. This standard should apply to every future metric in the `Custom/PatchExecution` namespace, not just this one.

### 3.3 The two-event-class finding

SSM emits two distinct event types for a patch run, and they are not interchangeable:

| Event | Fires when | Carries `instance-id`? |
|---|---|---|
| `EC2 Command Invocation Status-change Notification` | The patch ran on the instance and failed | **Yes** |
| `EC2 Command Status-change Notification` | The run never reached the instance | **No — there was no invocation** |

When the SSM agent is offline, the managed instance is deregistered, or **Project NAP stops the instance mid-window**, an invocation event may never be emitted at all. The failure surfaces only at the command level as `Undeliverable`, `Incomplete` or `DeliveryTimedOut`.

A single invocation-level rule silently misses exactly the failures listed under *EC2 State-Aware Patch Failure Alerting* in the capability document. Two rules are required — and the split is precisely what lets us satisfy the "differentiate operational/environmental failures from patch installation failures" criterion.

### 3.4 The correlation finding

`AWS-RunPatchBaseline` writes stdout to S3 at:

```
patchingsolution/<command-id>/<instance-id>/awsrunShellScript/<plugin>/stdout
```

**The command ID is in the object path.** Once a failure event is indexed in Splunk with `command_id` as a field, it joins natively to the stdout we already ingest. One search takes an engineer from *"a failure fired at 02:14 in account X"* to the actual package-manager error text — no console, no account hopping, no hand-built S3 paths.

This is the single strongest argument for capturing command ID, and it only works if command ID is an indexed field rather than a metric dimension.

### 3.5 The silent-success finding

`AWS-RunPatchBaseline` can report `Success` while individual patch installs or the S3 log upload failed. **This design catches hard terminal failures only.** It complements stdout parsing in Splunk; it does not replace it. Both paths are needed, and the proposal should not be sold as covering silent partial failures.

### 3.6 The divergence finding

Stdout and stderr are already written and indexed **on success as well as failure**. That is more useful than it first appears, because it means we will hold two independent records of the same run — the SSM event and the command output — sharing `command-id` as a join key (3.4).

Comparing them detects a failure mode neither stream reveals alone:

| Event says | stdout object exists | Interpretation |
|---|---|---|
| `Success` | yes | Ran, output captured. Normal. |
| `Success` | **no** | **The run's own S3 log upload failed silently.** Currently invisible. |
| `Failed` | yes | Ran and failed. The stdout carries the actual reason. |
| `Failed` | no | Failed before producing output, or the upload also failed. |
| *(no event)* | yes | Event pipeline is broken — the observability solution itself has rotted. |
| *(no event)* | no | Never ran, or the instance is out of scope. Needs the inventory join. |

The last two rows are worth noting: the divergence check is also a **self-test of this solution**, independent of the canary. It reframes coverage validation from "build a denominator" to "join two datasets we already have against inventory" — see section 10.

---

## 4. Options considered

| # | Option | Verdict |
|---|---|---|
| A | Wrapper runbook around `AWS-RunPatchBaseline` | **Rejected** — the centralised solution owns the invocation. No interception point exists. |
| B | Per-failure-reason detection scripts on each instance | **Rejected** — open-ended failure surface, unmaintainable, every unhandled case is a silent gap. |
| C | EventBridge → CloudWatch Logs → metric filter, no archive | **Insufficient alone** — gives detection and 365-day in-account triage, but no org-wide history, no Splunk index, no audit trail. Retained as the foundation of the recommendation. |
| D | EventBridge → central event bus → Firehose → S3 | **Rejected** — opaque object keys, minutes of buffering for a trickle of events, and no control over the format `s3tofirehose` consumes. Adds a central component. |
| E | EventBridge → central bus → single central Lambda → S3 | **Rejected** — a shared choke point (one account's failure storm throttles the archive for 449 others), region-bound bus, and a new cross-account trust mechanism alongside the one we already have. |
| **F** | **EventBridge + Lambda in every account → cross-account S3** | **Recommended.** |

### Why F

**It reuses trust we already operate.** The bucket already accepts writes from all 450 accounts via an org-scoped `ArnLike arn:aws:iam::*:role/aftwld-*-ec2-*` statement for AFT-vended instance profiles. Adding one more org-scoped statement for a fixed-name writer role is a smaller change than standing up a bus, a bus policy, and 450 forwarder roles.

**Blast radius is isolated.** No shared choke point. One noisy account cannot affect the other 449.

**Multi-region is free.** A central bus is region-bound and would need one per region. Per-account writers reach the same bucket from anywhere.

**The central account owns no compute.** It owns a bucket policy statement, a KMS statement, and an Athena table. Nothing to operate, patch, or page on.

**The honest trade-off:** ~450 Lambda functions carry a runtime-deprecation obligation. This was initially judged prohibitive, then reassessed — under AFT account customizations a runtime bump is one merge request and a fleet re-apply, the same motion as any other change. It is a real obligation, not a per-account one. Documented as risk R3.

---

## 5. Recommended architecture

```
MEMBER ACCOUNT  (× ~450, identical, via AFT account customizations)

  SSM Run Command — AWS-RunPatchBaseline*
            │ terminal status event
            ▼
  EventBridge DEFAULT bus
    ├─ rule: invocation-failure   (per-instance, has instance-id)
    ├─ rule: command-failure      (never reached the instance)
    └─ rule: canary               (dormancy proof)
            │
            │  parallel fan-out — NOT failover
            │
            ├──► [1] local CloudWatch log group ──► metric filter
            │        365-day forensics                    │
            │                                             ▼
            │                            Custom/PatchExecution → Splunk Olly → team
            │
            ├──► [2] mirror into existing log group  (optional second copy)
            │
            └──► [3] Lambda ──► cross-account PutObject
                        │
                        ▼
   s3://<bucket>/patchingsolution-events/failures/dt=2026-08-25/<account>/
        Failed_i-0abc123_3f2c8d91_20260825T021407Z_<event-id>.json
                        │
                        ▼   (existing pipeline, unchanged)
                 s3tofirehose ──► Splunk index
```

### Three tiers, one payload

| Tier | Store | Latency | Cardinality | Job |
|---|---|---|---|---|
| **Detect** | CloudWatch metric | seconds | LOW — enforced | Splunk Olly pages a team |
| **Triage** | CloudWatch Logs, in-account | seconds | full | Logs Insights pivot by instance/command |
| **Archive** | S3 → existing Splunk pipeline | ~1 s | full | index, org trend, audit, Athena |

**The metric is not optional.** S3 cannot alert, and Athena is a minutes-latency query tool. With no SNS or SES in the org, the CloudWatch metric is the only path to a notification.

**The three targets fire in parallel, always.** This is not a failover chain — EventBridge cannot express "try A, else B." Each target is independent, so a broken log group has no effect on the S3 record and vice versa. That independence *is* the redundancy.

### The object key carries the identifiers

```
Failed_i-0abc123_3f2c8d91_20260825T021407Z_a1b2c3d4.json
└stat┘ └instance┘ └command┘ └─timestamp──┘ └event-id┘
```

An engineer can find a specific failure with an `aws s3 ls` prefix listing — no Athena, no Splunk, no console. The event ID in the key makes at-least-once delivery idempotent: a retry overwrites the same object rather than duplicating it.

**Detailed diagrams:** see `patch-failure-observability.drawio` (single-account HLD + LLD), `patch-failure-observability-org-fanin.drawio` (org topology, dormancy, CI/CD) and `patch-failure-observability-splunk-ingestion.drawio` (ingestion contract).

---

## 6. Spike — questions to resolve before building

**Timebox: 3–5 days.** No code is written until S1–S4 are answered; they can invalidate the design.

### Blocking

| ID | Question | Method | Owner |
|---|---|---|---|
| **S1** | What is the archive bucket's Object Ownership setting — `BucketOwnerEnforced`, or ACLs enabled? | `aws s3api get-bucket-ownership-controls`; then write a test object cross-account and read it back **from the central account** | Platform + Logging |
| **S2** | Does `EC2 Command Status-change Notification` actually fire for Patch Manager runs in our environment? | Enable a temporary catch-all rule in operations-dev, run a patch cycle, inspect the captured events | Platform |
| **S3** | Does the existing bucket policy contain an explicit `Deny` that would catch a new writer role? | Read the current bucket policy | Logging |
| **S4** | Do SCPs, permission boundaries, or Declarative Policies restrict `lambda:CreateFunction`, mandate a boundary, or force Lambda into a VPC? | Review org guardrails; attempt a trial function in operations-dev | Platform + Security |

> **Why S4 matters:** if Lambda is forced into a VPC, it needs an S3 gateway endpoint and a KMS interface endpoint or every invocation hangs until timeout. That is a design change, not a config tweak.

### Non-blocking but needed before fleet rollout

| ID | Question | Owner |
|---|---|---|
| S5 | How does `s3tofirehose` discover new objects — S3 notifications, EventBridge, or a scheduled scan? | Logging |
| S6 | Is that discovery rule prefix-scoped, and would it cover a new sibling prefix? | Logging |
| S7 | If it uses `aws_s3_bucket_notification` — that resource is **authoritative for the entire bucket**. A second one silently wipes the existing config and breaks ingestion for every account. Can our prefix be added to *their* resource, or can we move to EventBridge S3 notifications? | Logging |
| S8 | Confirm a **new** Splunk sourcetype. Reusing the stdout sourcetype makes the JSON parse as garbage into the wrong index — which looks successful from the AWS side. | Observability |
| S9 | Does `source` carry the S3 object key in the existing Splunk pipeline, or is it `s3_key`/metadata? The stdout-join search depends on it. | Observability |
| S9b | Is stdout/stderr written and indexed for **every** successful invocation, or only on certain plugins/platforms? Windows uses `awsrunPowerShellScript` rather than `awsrunShellScript` — confirm both land. This underpins the coverage and divergence work. | Observability + Platform |
| S10 | Is patching single-region? The design supports multi-region natively, but the bucket, CMK and Athena table are single-location. | Platform |

### Prefix decision arising from S5–S7

We propose landing at a **sibling** prefix — `patchingsolution-events/` rather than inside `patchingsolution/`. If the existing labeling rule sweeps up the new objects and tags them with the stdout sourcetype, they parse as garbage into the wrong index. A sibling prefix makes the new sourcetype an explicit, deliberate addition.

---

## 7. POC scope

**Timebox: 5–8 days build, 3–5 days validation.**

### In scope

- One reusable Terraform module (member-account), built to platform module standards with validated inputs, semver release, and an example
- Deployed to **two accounts**: operations-dev and one representative application account
- Both event rules, both metric filters, the local log group tier, and the Lambda → S3 archive tier
- The dormancy canary and both dead-letter queues
- Athena table with partition projection
- Splunk `props.conf` and saved searches, handed to Observability — including the **event-vs-stdout divergence search** (3.6), which detects silent S3 log-upload failures and is the highest-value single search this work unlocks
- Bucket policy and KMS key policy statements, rendered as outputs and handed to the bucket owner
- Chaos validation: deliberately break each path and confirm the failure is visible

### Explicitly out of scope

| Item | Why |
|---|---|
| Fleet rollout | Gated on POC go/no-go |
| Project NAP integration | NAP team inputs still outstanding. The command-level `DeliveryTimedOut` counter gives a *signal* of collisions; proving causation is separate work. |
| Coverage validation — the inventory join | Section 10. Smaller than first assessed (stdout already supplies the observed set), but needs its own scoping. |
| Silent partial-failure detection | Section 3.5 — needs stdout parsing, already owned elsewhere |
| Automated remediation | Detection first. Remediation without reliable detection is guesswork. |
| Non-AFT accounts (management, Log Archive, Audit) | Needs a StackSet or dedicated workspace; deferred to rollout planning |

---

## 8. Go / no-go criteria

The POC proceeds to fleet rollout only if **all** of these hold.

### Correctness

- [ ] A forced failure produces a record in **all three tiers** within expected latency
- [ ] The metric appears in `Custom/PatchExecution` with exactly `AccountId` and `Status` — **and no other dimensions**
- [ ] The S3 object key contains account, status, instance-id, command-id and timestamp
- [ ] **The object is readable from the central account** — the object-ownership check (S1). This must be verified from the bucket owner's side; from the writing account it always looks fine.
- [ ] Both Logs Insights queries resolve `instance_id` and `command_id`
- [ ] The Athena table returns rows with no `MSCK REPAIR`
- [ ] `s3tofirehose` picks up the new prefix and Splunk shows the correct index and sourcetype
- [ ] The stdout-join search (3.4) returns the actual error text for a real failure
- [ ] The divergence search (3.6) runs clean over one full patch cycle, and any `Success`-with-no-stdout rows are investigated rather than dismissed
- [ ] With `capture_success = true`, success events produce a **metric only** — confirm no success objects appear in the S3 archive prefix

### Failure visibility (chaos tests)

- [ ] Remove the bucket policy statement → Lambda DLQ depth rises, `AWS/Lambda Errors` ticks, the function logs AccessDenied
- [ ] Remove the KMS statement → same
- [ ] Remove the Lambda invoke permission → EventBridge target DLQ rises, `AWS/Events FailedInvocations` ticks
- [ ] Restore all three → recovery with no manual replay beyond draining the DLQs

### Cost and scale

- [ ] Metric count per account matches the ~4 projection; CloudWatch billing dimensions confirm it
- [ ] With `rules_enabled = false`, the account's cost attributable to this solution is **$0**

### Stakeholder acceptance

- [ ] Observability confirms the sourcetype, index and searches are workable
- [ ] Logging confirms the prefix and bucket/KMS policy changes are acceptable
- [ ] Cloud Operations confirms the metric and searches give them what they need to track failures to resolution
- [ ] Security confirms the writer role's least-privilege scope and the org-scoped conditions

**No-go triggers:** S1 reveals an ownership model we cannot satisfy; S2 shows command-level events do not fire (design must change); S4 forces Lambda into a VPC without available endpoints.

---

## 9. Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| **R1** | Cross-account object ownership misconfigured — writes succeed, bucket owner cannot read, `s3tofirehose` sees nothing, no error anywhere | Medium | **High** | S1 is blocking; go/no-go includes a read-back **from the central account** |
| **R2** | `s3tofirehose` claims the new prefix with the stdout sourcetype — parses as garbage into the wrong index while looking successful | Medium | High | Sibling prefix; explicit new sourcetype confirmed with Observability (S8) |
| **R3** | Runtime deprecation across 450 Lambda functions | High (certain, on AWS's schedule) | Low | One MR + AFT fleet re-apply. Zero dependencies means no supply chain to manage. Track EOL dates in the platform backlog. |
| **R4** | Silent rot — a policy edit 8 months from now breaks a dormant solution, discovered on the night it was needed | **High** | High | Weekly canary; two DLQs; `FailedInvocations` / `Errors` / DLQ depth watched by Splunk; TFE drift detection enabled |
| **R5** | Someone adds a high-cardinality metric dimension later | Medium | High (cost) | Module variable validation + OPA plan-time gate |
| **R6** | A second `aws_s3_bucket_notification` wipes the existing bucket configuration | Low | **Very high** — breaks patch logging for all 450 accounts | S7 blocking before rollout; explicit prohibition in the implementation spec |
| **R7** | Alert noise once detection works — we start seeing failures that were always there | Medium | Medium | Expected and healthy. Wave-based rollout lets Cloud Operations tune before fleet scale. |
| **R8** | Command-level events do not fire as assumed | Low | Medium | S2 blocking; validated in operations-dev before any build |

---

## 10. Coverage validation — what this closes, and what is left

An earlier draft of this proposal claimed the design could not distinguish *"patching is healthy"* from *"patching never ran."* That was overstated, because it ignored an asset we already have.

### The denominator largely exists today

`AWS-RunPatchBaseline` writes stdout and stderr **on success as well as failure**, to `patchingsolution/<command-id>/<instance-id>/...`, and that content is already indexed in Splunk. So *"which instances produced patch output this cycle"* is answerable now, with instance ID and command ID recoverable from the object path.

What is missing is therefore **not the observed set — it is the expected set.** Coverage validation reduces to joining the observed instances against inventory (Patch Group / `patch:wave` tags, or AWS Config / SSM Inventory). That is materially less work than building a success-capture pipeline from scratch, and it changes the recommendation in section 7.

### Three gaps survive

| Gap | Why stdout cannot close it |
|---|---|
| **Runs that never reached an instance** — agent offline, managed instance deregistered, instance stopped mid-window by Project NAP | No invocation means no output object at all. Absence is indistinguishable from "out of scope" or "instance no longer exists." Only the **command-level event** carries this. |
| **Silent S3 upload failure** — the run succeeds but its own log upload does not | No stdout object exists, so absence of stdout ≠ absence of run. Any coverage figure built on stdout alone produces a false negative here. |
| **The expected set** | Neither stream knows what *should* have been patched. Requires an inventory join. |

### The gap that becomes a capability

Cross-checking the two streams detects the second row above directly:

> **Event says `Success` + no stdout object for that command ID → the log upload failed silently.**

This is a known blind spot in `AWS-RunPatchBaseline` that is currently invisible. It becomes detectable only because both streams exist, and only because the command ID is the join key between them (finding 3.4). It is arguably the highest-value single search this work unlocks, and it costs nothing extra to build.

### Consequence for the design

`capture_success` should produce a **metric only**, not an archived object:

| | Success as a CloudWatch metric | Success archived to S3 |
|---|---|---|
| Value | seconds-fresh count, low cardinality, scraped by Olly; **present even when the stdout upload fails** | duplicates what stdout already provides |
| Cost | ~1 extra metric/account (~$135/mo fleet-wide) | ~90k objects/month across the fleet, degrading Athena over the failure archive |

**Recommendation: the success rule attaches to the log-group target only, never to the Lambda/S3 target.** This is specified in Annex A and is a deliberate asymmetry, not an oversight.

### Revised position on the acceptance criterion

This proposal **substantially advances** the "Patch Execution Coverage Validation" criterion — it supplies the command-level signal that stdout structurally cannot, and the divergence check that catches silent upload failures. It does **not** fully satisfy it, because the inventory join is out of scope here.

> **Recommendation:** scope the inventory join **before** fleet rollout, even if delivered after. It is now a modest piece of work rather than a second pipeline — but retrofitting it across 450 accounts is still a second rollout.

---

## 11. Inputs needed

| From | What we need | Blocking? |
|---|---|---|
| **Logging / bucket owner** | Object Ownership setting (S1); current bucket policy (S3); `s3tofirehose` discovery mechanism and prefix scoping (S5–S7); agreement to merge two policy statements | S1, S3 yes |
| **Observability / Splunk** | A new sourcetype and target index (S8); confirmation of how the object key surfaces as a field (S9); review of the five saved searches | Before rollout |
| **Security** | Confirmation that SCPs and boundaries permit the writer role and Lambda (S4); review of least-privilege scope | S4 yes |
| **Centralised Patching Solution team** | Confirmation that `AWS-RunPatchBaseline` invocation remains via Run Command (not State Manager association only), which determines event shape | S2 related |
| **Cloud Operations** | Review of the metric and searches against how they actually triage | Before go/no-go |
| **Project NAP team** | Not blocking. Deferred — noted only so it is not assumed in scope. | No |

---

## 12. Cost

| | |
|---|---|
| **At rest (dormant)** | **$0.** EventBridge service-event matching on the default bus is free; empty log groups, empty SQS queues and un-invoked Lambdas are free; a metric filter that never fires creates no metric and bills nothing. |
| **Active, full fleet** | **~$540/month** (~4 metrics × $0.30 × 450 accounts), plus negligible Lambda invocations, S3 storage and CloudWatch Logs ingestion. |
| **Design rejected on cost** | ~$27,000/month, if instance ID were used as a metric dimension (3.2). |
| **Engineering** | ~3 weeks, one engineer, for spike + POC + validation. Rollout effort estimated separately after go/no-go. |

Cost is not the driver here — even the Lambda path is effectively free at this volume. The number that matters is the one we **avoided**: the cardinality finding is worth ~$320k/year and applies to every future metric in this namespace, not just this capability.

---

## 13. Path to production

Assuming go:

| Wave | Scope | Gate |
|---|---|---|
| **0** | POC accounts, `capture_success = true`, canary on | Section 8 criteria |
| **1** | 10 accounts via AFT account customizations, deployed **armed** | Metric count matches projection; no DLQ traffic; Splunk ingestion clean for 2 patch cycles |
| **2** | Full AFT-vended fleet, deployed **dormant** (`rules_enabled = false`) | Terraform applies cleanly at scale; $0 cost confirmed |
| **3** | Arm the fleet — one variable flip | Cloud Operations ready for the alert volume |
| **4** | Non-AFT accounts (management, Log Archive, Audit) via StackSet | — |

Then: weekly canary added to the existing pipeline that rolls `ApproveUntilDate`; TFE drift detection enabled on these workspaces; runbook published; KT to Cloud Operations.

---

## 14. Reusability — why this compounds

Framing this as a one-off patch-failure tool undersells it. What the build actually produces is a **reusable pattern for turning any AWS service event into a low-cardinality alert plus a high-fidelity archived record**, deployed fleet-wide at zero idle cost.

Patch failures are the first tenant. Backup job failures, Config non-compliance, and GuardDuty findings could use the same module with a different event pattern and a different S3 prefix. The module would need one additional variable.

Two things should become platform standards regardless of what happens to this capability:

1. **The cardinality rule**, enforced by OPA at plan time — no high-cardinality metric dimensions, anywhere, by anyone.
2. **The dormancy pattern** — deploy disabled, arm with one variable, prove liveness with a canary, watch `FailedInvocations` and DLQ depth. Any fleet-wide solution that sits idle needs this, and none of ours currently have it.

Worth raising at CCoE review, because it changes how the cost and effort of this work should be evaluated.

---

## 15. Ask

Approval for:

1. **A 3–5 day spike** to resolve S1–S4, with S1 and S4 as potential no-go findings
2. **A 5–8 day POC build** plus 3–5 days validation in two non-production accounts
3. **Inputs from Logging, Observability and Security** per section 11
4. **A go/no-go review** against section 8 on completion

Implementation detail — module structure, resource-by-resource specification, IAM policies, handler code, and the full anti-pattern list — is in **Annex A: `BUILD-SPEC-patch-failure-observability.md`**, which becomes the implementation artifact if this is approved.
