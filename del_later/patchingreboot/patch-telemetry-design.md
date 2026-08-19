# Patch Execution Telemetry — Reboot & Status Reporting to CloudWatch

**Scope:** In-place patching observability for EC2 across ~400–500 AWS accounts (Control Tower + AFT).
**Target OS:** Amazon Linux 2 / 2023, RHEL, Windows Server.
**Status:** Design complete, pending single-account validation and cross-team confirmations.

---

## 1. Problem Statement

The centralized patching solution runs `AWS-RunPatchBaseline` on a weekly cadence across
wave-based policies (`dev-a`, `dev-b`, `test-a`, `test-b`, `prd-a`, `prd-b`). The patch
baseline is locked on the **15th of every month** (non-negotiable), so from the 15th
onward the approved patch content is frozen for the cycle.

Two things need to be true:

1. **App teams must be told when an instance actually reboots** — not when a patch job
   merely ran. A weekly notification for every wave is noise; a missed reboot
   notification is an incident.
2. **Patch status must be visible centrally** — success, failure, and coverage — without
   SNS/SES/email, since notification is owned by Splunk Observability ("Olly") scraping
   CloudWatch.

**Core difficulty:** an OS-level reboot does not change EC2 instance state. The instance
stays `running`, so there is no EC2 state-change event to catch. The reboot signal has to
be derived.

---

## 2. Constraints

| Constraint | Detail |
|---|---|
| Baseline lock | 15th of every month, via `approve_until_date` (not `approve_after_days`) |
| Patch cadence | Weekly waves; baseline content unchanged within a cycle |
| Invocation ownership | Centralized patching solution owns `AWS-RunPatchBaseline`; we cannot wrap it |
| Notification | Splunk Olly only, scraping CloudWatch. No SNS, SES, or email infrastructure |
| Scale | Must work across 400–500 accounts with no per-onboarding edits |
| Out of scope | Project NAP (power management), EMR exclusion |
| Deployment | `aft-global-customizations` for workload accounts; StackSet for management/Log Archive/Audit |

---

## 3. Key Findings (validated during design)

### 3.1 `RebootOption` semantics

Per AWS documentation, with `RebootIfNeeded` the node reboots when **either**:

- Patch Manager installed one or more patches (regardless of whether the patch itself
  requires a reboot), **or**
- Patch Manager detects patches in `INSTALLED_PENDING_REBOOT` during `Install`.

`NoReboot` **defers** a reboot rather than avoiding it — the pending-reboot state persists
and the next `Install` with `RebootIfNeeded` will trigger it. This must be stated plainly
in the app-team contract.

**Observed in testing:** with a frozen baseline, weekly `Install` runs are quiet — reboot
occurs only when new baseline content lands or the AMI is rotated. **Caveat:** an app team
running `yum update` out-of-band mid-cycle leaves `INSTALLED_PENDING_REBOOT`, which the
next weekly `Install` will flush as a reboot with no new patches installed.

### 3.2 Reboot sequencing inside the Run Command

The patch script signals reboot via exit code **194** (Linux) / **3010** (Windows). SSM
Agent then:

1. Notifies the SSM service that communication will be disrupted
2. Reboots the node
3. Restarts the script after the reboot completes
4. Reports terminal status

**Implication:** the reboot happens *inside* the Run Command invocation. Any post-patch
check triggered on terminal status is guaranteed to find the agent online. There is no
race condition.

### 3.3 Silent failure mode

`AWS-RunPatchBaseline` can report `Success` even when individual patch installs or the S3
log upload fail. Status alone is not sufficient evidence of a healthy patch run.

### 3.4 EventBridge cannot target Run Command dynamically

An EventBridge `RunCommandTarget` accepts only literal `InstanceIds` or `tag:key` values,
and input-transformer variables do **not** resolve inside those values. A Run Command
target therefore cannot aim at the instance named in the event.

**SSM Automation targets do support the input transformer.** This is why the trigger is an
Automation runbook, not a direct Run Command target and not a Lambda.

### 3.5 Reboot detection is one inequality

```
rebooted  ⟺  boot_epoch > patch_start_epoch
          ⟺  uptime_seconds < (now − patch_start_epoch)
```

Both forms are equivalent (`boot_epoch = now − uptime`). All detection methods below are
just different ways of obtaining `boot_epoch`.

---

## 4. Architecture

### 4.1 Primary path — parse `AWS-RunPatchBaseline` stdout (already in place)

`AWS-RunPatchBaseline` stdout/stderr is already routed to a central S3 bucket in the
operations account (KMS-encrypted, customer-managed multi-region key) and ingested into
Splunk.

**Data points available in that stdout:**

- Explicit reboot decision lines logged by the patch payload
  (e.g. `[INFO]: Reboot is not required`)
- **Structural signal:** because the agent restarts the script after a reboot, a rebooted
  run's stdout contains **two passes** — payload download and `os_selector` import appear
  twice within a single invocation
- Patch baseline id/name, patch group, operation type, per-patch results

**Risks accepted on this path:**

| Risk | Detail |
|---|---|
| Format is not a contract | Payload is downloaded at run time (`patch-baseline-operations-1.110`, `1.132`, …). AWS revs wording without notice |
| Fails silent | If the S3 upload fails, no log reaches Splunk and nothing alarms |
| "Required" ≠ "occurred" | A reboot-required line is not proof a reboot happened; `NoReboot` cohorts log requirement without the event |
| Per-OS dialects | Windows uses a separate PowerShell module with different wording |

**Bucket policy note (already resolved):** AFT-vended IAM roles carry generated suffixes,
so the bucket policy uses an org-scoped `ArnLike` pattern
(`arn:aws:iam::*:role/aftwld-*-ec2-*`) rather than a fixed role ARN.

### 4.2 Backup path — event-driven detection publishing to CloudWatch

Deterministic, fails loud, independent of log format.

```
Centralized patching solution
        │
        │ runs AWS-RunPatchBaseline (Install)
        ▼
   SSM Run Command  ──── reboot happens INSIDE this invocation (exit 194/3010)
        │
        │ terminal status → EventBridge event
        ▼
EventBridge rule  (source: aws.ssm,
                   detail-type: EC2 Command Invocation Status-change Notification,
                   document-name: AWS-RunPatchBaseline*,
                   status: Success|Failed|TimedOut|Cancelled)
        │
        │ input transformer: instance-id, command-id, status, requested-date-time
        ▼
SSM Automation:  Trigger-DetectPatchReboot
        │  • converts requested-date-time → patch start epoch (the time anchor)
        │  • looks up Operation via ListCommands → Scan runs exit here, silently
        │  • resolves Name + patch:wave tags for metric dimensions
        ▼
SSM Command doc: Detect-PatchReboot   (runs ON the instance)
        │  • boot_epoch vs patch_start_epoch
        │  • publishes both metrics
        │  • prints forensic evidence for Splunk
        │  • exits nonzero if publish fails
        ▼
CloudWatch namespace: Custom/PatchExecution
        ▼
Splunk Observability (scrape) → app-team reboot notification / Cloud Ops failure alert
```

**Fallback:** if the instance is unreachable or the on-instance publish fails, the
Automation runbook publishes `PatchRunStatus` plus `RebootDetectionFailed` centrally under
its own role. A broken instance cannot report its own breakage, so this closes the gap.

### 4.3 Why the two paths coexist

| | Primary (stdout) | Backup (metric) |
|---|---|---|
| Answers | *What* was installed and why | *Whether* the box rebooted |
| Failure mode | Silent | Loud (`RebootDetectionFailed`) |
| Format stability | Undocumented, drifts | Controlled by us |
| Best role | Evidence / drill-down | Notification trigger |

**Recommended split:** metric is the trigger, log is the evidence. Notification links app
teams to the Splunk log for detail.

**Reconciliation search** (catches drift in either signal):

```spl
| mstats sum(RebootOccurred) as metric_reboots WHERE index=cw_metrics ... by InstanceId
| join InstanceId [ search index=patch_logs "Reboot" | stats count as log_reboots by InstanceId ]
| where metric_reboots != log_reboots
```

---

## 5. Metric Schema

**Namespace:** `Custom/PatchExecution` (proposed — see Q1 in §8)

| Metric | Value | Dimensions | Published by |
|---|---|---|---|
| `PatchRunStatus` | 1 | `InstanceId`, `InstanceName`, `Wave`, `Status` | Instance (normal), Automation (fallback) |
| `RebootOccurred` | 1 or 0 | `InstanceId`, `InstanceName`, `Wave` | Instance |
| `RebootDetectionFailed` | 1 | `InstanceId`, `InstanceName`, `Wave` | Automation (fallback only) |

`Status` values: `Success`, `Failed`, `TimedOut`, `Cancelled`.

**Existing related namespace:** `Custom/PatchCompliance` (EMF via per-account Lambda,
driven by Run Command terminal status and compliance state-change events). Consolidation
question in §8.

**Machine-readable markers in the detection doc's stdout** (for Splunk field extraction):

```
NOW_EPOCH=...
BOOT_EPOCH=...
UPTIME_SECONDS=...
PATCH_START_EPOCH=...
PATCH_STATUS=Success|Failed|TimedOut|Cancelled
REBOOTED=true|false
METRIC_PUBLISHED=true|false
```

---

## 6. Detection Method Menu

The Command document ships **all** methods per OS. The kernel-truth method is active;
alternatives are present as labeled, commented blocks for swap-in at implementation time.

### Linux (AL2 / AL2023 / RHEL — all systemd, identical primitives)

| # | Method | Notes |
|---|---|---|
| 1 ✅ | `awk '/btime/ {print $2}' /proc/stat` | Kernel boot epoch. No timezone/locale/parsing. **Active** |
| 2 | `/proc/uptime` first field | Kernel uptime seconds; same inequality, uptime form |
| 3 | `uptime -s` | systemd boot time, **local time** — convert explicitly |
| 4 | `who -b` | utmp boot time, local time, locale-dependent format |
| 5 | `last reboot -F` | Reboot history from wtmp; wtmp rotates |
| 6 | `journalctl --list-boots` | Boot sessions; needs persistent journal storage |
| ❌ | `needs-restarting -r` | Reports reboot **required**, not **occurred**. Never use for this decision |

### Windows Server

| # | Method | Notes |
|---|---|---|
| 1 ✅ | `(Get-CimInstance Win32_OperatingSystem).LastBootUpTime` via `DateTimeOffset` | Explicit timezone handling, locale-independent. **Active** |
| 2 | `[Environment]::TickCount64` | Milliseconds since boot |
| 3 | `Get-Uptime -Since` | PowerShell 6+ only — not on Windows PowerShell 5.1 |
| 4 | Event ID **6005** | Event log service started — boot marker |
| 5 | Event ID **1074** | Records **which process initiated** the shutdown → patch reboots are directly attributable. Strongest for audit; pair with #1 for the decision |
| ❌ | `systeminfo`, `wmic` | Slow/locale-formatted; `wmic` deprecated |

Additional Windows evidence captured: **6006** (clean shutdown), **6008** (unexpected).

---

## 7. Deliverables

| Artifact | Type | Purpose |
|---|---|---|
| `detect-patch-reboot.yaml` | SSM Command doc (schema 2.2) | On-instance detection + metric publish + forensic output |
| `trigger-detect-patch-reboot.yaml` | SSM Automation runbook (schema 0.3) | EventBridge target; resolves context, filters Scan, dispatches detection |
| `terraform/patch-reboot-telemetry/` | Terraform module | Both documents, both IAM roles, EventBridge rule + input transformer, optional instance policy |

### IAM summary

**Automation execution role**

| Action | Scope |
|---|---|
| `ssm:ListCommands` | `*` (no resource-level support) |
| `ec2:DescribeInstances` | `*` |
| `ssm:SendCommand` | Detection doc ARN + instance ARNs |
| `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations` | `*` |
| `cloudwatch:PutMetricData` | Condition: `cloudwatch:namespace = Custom/PatchExecution` |

**EventBridge role:** `ssm:StartAutomationExecution` on the automation-definition ARN,
`iam:PassRole` on the Automation role (condition `iam:PassedToService = ssm.amazonaws.com`).

**Instance profile:** `cloudwatch:PutMetricData` scoped by `cloudwatch:namespace` condition.
Trade-off: any process on the instance can then write to that one namespace. Alternative is
to move publication fully into the Automation role and have the instance only report — see
Q9 in §8.

**Prerequisite:** AWS CLI v2 on the instance. Preinstalled on AL2023; must be baked into
RHEL and Windows golden AMIs. Absent CLI = loud failure, not a silent gap.

---

## 8. Questions for the Observability / Splunk Olly Team

> These block the metric path from producing notifications. Highest priority first.

**Q1 — Namespace onboarding.**
Is `Custom/PatchExecution` scraped today, or does a new namespace require explicit
onboarding? What is the lead time? Should this instead fold into the existing
`Custom/PatchCompliance` namespace to avoid a second onboarding?

**Q2 — Metric cardinality / MTS budget.**
Dimensions are `InstanceId` + `InstanceName` + `Wave`. Across 400–500 accounts this is one
metric time series per instance per metric. What is the MTS budget, and is per-instance
cardinality acceptable? If not, the fallback is wave-level alerting with app teams pivoting
to the Splunk log for the instance list. **Decision needed before fleet rollout.**

**Q3 — Sparse vs dense metrics.**
`RebootOccurred` publishes `0` on no-reboot runs. Does Olly prefer explicit zeros (dense,
easier "did it run" checks) or only `1` values (sparse, lower cardinality/cost)? This
changes detector logic and the document.

**Q4 — Scrape interval and latency.**
How long between `PutMetricData` and the datapoint being alertable in Olly? App teams will
ask "how soon after the reboot do I hear?"

**Q5 — Cross-account collection.**
Metrics are published in each *workload* account. How does Olly collect across 400–500
accounts today — per-account scrape, cross-account observability, or a metric stream? Does
anything need enabling per account as part of AFT customization?

**Q6 — Detector ownership and routing.**
Who builds and owns the detectors? Proposed:

| Detector | Condition | Route to |
|---|---|---|
| Reboot notification | `RebootOccurred == 1` | App team owning the instance |
| Patch failure | `PatchRunStatus{Status=Failed} >= 1` | Cloud Operations |
| Detection gap | `RebootDetectionFailed >= 1` | Cloud Platform (hygiene) |

How is "app team owning the instance" resolved — from `InstanceName`, `Wave`, an account
mapping, or a tag we need to add?

**Q7 — Dimension naming conventions.**
Any required naming standards or reserved dimension names we should conform to?

**Q8 — Retention.**
Metric retention in Olly, and is that sufficient for month-over-month patch coverage
reporting?

**Q9 — Publication mechanism preference.**
Three options; which does the team prefer?

1. `PutMetricData` from the instance (current design — instance needs scoped IAM)
2. `PutMetricData` from the Automation role (no instance IAM, but the doc must return the
   verdict to the runbook)
3. EMF via CloudWatch Logs (matches existing `Custom/PatchCompliance` pattern)

**Q10 — Missing-data alerting.**
Can Olly alert on *absence* of expected datapoints? This is how we catch "patch ran but
telemetry never arrived," which is the silent failure mode we already know exists.

---

## 9. Questions for the Logging Team (Splunk log ingestion)

**L1.** Which index receives `AWS-RunPatchBaseline` stdout today, and what field
extractions already exist?

**L2.** Are **Windows** patch logs ingested as well as Linux, or Linux only? The Windows
PowerShell module output is a different dialect and needs its own extractions.

**L3.** Can field extractions be added for the detection document's markers
(`REBOOTED=`, `PATCH_STATUS=`, `METRIC_PUBLISHED=`, `BOOT_EPOCH=`)?

**L4.** Can an alert be created for **"command reported Success but no log arrived"**? This
closes the known silent S3-upload failure gap and is required if the log path is ever to be
the notification trigger.

**L5.** Log retention vs metric retention — are they aligned for reconciliation searches?

**L6.** Should the detection document's stdout route to the **same** central S3 bucket and
prefix as the patch logs, or a separate prefix? (Recommend same bucket, separate prefix.)

---

## 10. Questions for the Centralized Patching Solution Owner

**P1 — Which document is actually invoked?**
`AWS-RunPatchBaseline`, `AWS-RunPatchBaselineAssociation`, or
`AWS-RunPatchBaselineWithHooks`? Quick Setup patch policies commonly use the **Association**
variant. The EventBridge pattern currently matches all three, but confirmation lets us
tighten it.

**P2 — Is `AWS-RunPatchBaselineWithHooks` available to us?**
It supports lifecycle hooks including one **after the reboot** — that would be a native
insertion point and could replace the EventBridge trigger entirely. Requires SSM Agent
3.0.502+.

**P3 — Per-wave `RebootOption`.**
Can `RebootIfNeeded` vs `NoReboot` be set per wave/cohort? This determines whether reboot
policy ownership can be delegated per cohort. Note: `NoReboot` defers, never avoids.

**P4 — Install-once suppression. ⚠️ OPEN DESIGN GAP**
The original design blocked repeat installs within a cycle via a wrapper runbook with a
monthly cycle gate (tag `patch:cycle`, Scan-only path on repeat). That approach depended on
controlling the invocation, which we do not. **What lever exists instead?**
- Tag-based exclusion the centralized solution honors?
- Per-wave Maintenance Window targeting?
- A supported pre-hook?

Note the observed behavior mitigates this substantially — with a frozen baseline, repeat
installs are quiet. But the out-of-band `yum update` case can still produce an unexpected
reboot. **Needs a decision.**

**P5 — Does the `patch:wave` tag exist?**
The metric dimension depends on it. If waves are expressed differently (patch group,
Maintenance Window name, account OU), the dimension source must change.

**P6 — Is stdout already routed to S3/CloudWatch by their configuration**, or is that ours
to configure?

---

## 11. Open Items

| # | Item | Owner | Blocking? |
|---|---|---|---|
| 1 | Install-once suppression lever (P4) | Patching solution owner | Yes — original requirement |
| 2 | Namespace onboarding + cardinality (Q1, Q2) | Observability | Yes — no notification without it |
| 3 | Publication mechanism decision (Q9) | Observability + Platform | Yes — changes IAM model |
| 4 | AWS CLI v2 in RHEL + Windows golden AMIs | AMI owner | Yes for those OS families |
| 5 | Instance profile `PutMetricData` via AFT base policy | Platform | Yes if option 1 chosen |
| 6 | AL2 validation (doc targets AL2023/RHEL primitives; identical on AL2 but untested) | Platform | No |
| 7 | Wave→app-team mapping for notification routing (Q6) | Observability + App teams | Yes |
| 8 | Baseline `approve_until_date` monthly bump pipeline + `lifecycle { ignore_changes = [approval_rule] }` | Platform | Already designed |

---

## 12. Validation Plan (single account before fleet)

1. **Deploy** the Terraform module to the validation account.
2. **Standalone document test** — run `Detect-PatchReboot` manually on one instance per OS
   family (AL2023, RHEL, Windows). Confirm stdout markers and a datapoint in
   `Custom/PatchExecution` within ~1 minute.
3. **Reboot-positive test** — patch an instance with a reboot-triggering package. Confirm:
   - Run Command invocation stays `InProgress` through the reboot, then flips to Success
     (proves the exit-194/3010 sequencing)
   - Automation execution starts from the EventBridge rule
   - `RebootOccurred = 1`, `PatchRunStatus{Status=Success} = 1`
4. **Reboot-negative test** — patch an already-current instance. Confirm `RebootOccurred = 0`.
5. **Scan-filter test** — run a `Scan` operation. Confirm the Automation exits early and
   **no** metrics are published.
6. **Failure-path test** — stop an instance mid-window or block its agent. Confirm the
   fallback publishes `PatchRunStatus{Status=Failed}` and `RebootDetectionFailed`.
7. **Reconciliation** — run the Splunk search in §4.3 for one full cycle and confirm the log
   and metric paths agree.
8. **Olly end-to-end** — confirm the datapoint is visible in Olly and a test detector fires.

---

## 13. Summary of Recommendation

- **Metric path = notification trigger.** Deterministic, fails loud, format under our control.
- **Log path = evidence.** Rich detail on what installed and why; linked from the notification.
- **Reconciliation search** runs continuously so drift in either signal surfaces on a
  dashboard rather than via an angry app team.
- **Do not** make the stdout log the sole trigger without first adding the
  "Success but no log arrived" alert (L4) — that design inherits a silent failure mode
  already observed in this environment.
