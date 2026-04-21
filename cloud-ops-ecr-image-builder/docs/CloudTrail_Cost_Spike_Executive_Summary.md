# CloudTrail Cost Spike — Executive Summary

> **Period:** February 5–17, 2026
> **Cost Increase:** ~600% peak
> **Security Impact:** None — logging functioned correctly throughout
> **Status:** Primary fix applied Feb 17, 2026. Two items remain open.

---

## What Happened

AWS CloudTrail costs increased by approximately **600%** beginning February 5–6, 2026, and continued at an elevated level on subsequent days through mid-February.

The spike was confirmed across two cost drivers in AWS Cost Explorer:

- **Paid management event recording** — AWS charges for API activity logs beyond the free baseline
- **CloudTrail Insights anomaly detection charges** — a separate charge triggered when AWS detects unusually high API activity volumes

---

## What Caused It

The root cause was a **compliance reporting automation job** that runs on a scheduled basis inside AWS ECS (Elastic Container Service). This job scans all AWS accounts in the organization for non-compliant resources and produces reports for remediation teams.

Two compounding issues drove the cost:

---

### Issue 1 — A design flaw in the automation code (active on every run)

The job was making one database lookup call for *every non-compliant resource it processed*, rather than looking up each account once and reusing the result for the rest of the run.

With thousands of non-compliant resources spread across hundreds of accounts, this generated thousands of unnecessary API calls per run — where only ~50–100 were needed. Every one of those calls is recorded as a paid CloudTrail event.

**This issue was present on every scheduled run, not just February 5–6.**

---

### Issue 2 — The job ran for ~12 continuous hours on February 5–6 (worst-case amplifier)

A normal run of this job completes in a fraction of that time. On February 5–6, the job ran for approximately 12 hours without stopping or timing out.

Because the unnecessary database calls happen on every resource iteration, a 12-hour run produced roughly **12× the normal event volume** — pushing the total far above the free-tier threshold and into paid territory across both active CloudTrail trails.

The exact reason the job ran for 12 hours is still under investigation. Likely contributors include a larger-than-normal non-compliant resource result set, or internal API rate-limiting causing the job to stall and retry repeatedly.

---

### Issue 3 — CloudTrail Insights charges compounding on top (secondary cost driver)

CloudTrail Insights is a monitoring feature that detects unusual API call patterns and charges separately when it triggers. Because the automation's API call volume was abnormally high on February 5 and again on February 11–13, Insights fired on both occasions.

This created a **compounding charge**: billed once for generating the events, and again for CloudTrail detecting that the volume was abnormal. Insights is visible as a prominent cost bar (`USE2-InsightsEvents`) in Cost Explorer on those dates.

---

## Why It Persisted Beyond February 5–6

The design flaw in the code was active on every subsequent scheduled run. Although no other run lasted 12 hours, each normal run still generated significantly more paid events than it should — visible as recurring cost spikes across the February 1–17 window.

| Period | Relative Cost | Driver |
|---|---|---|
| Feb 1–3 | Baseline | Normal |
| **Feb 5–6** | **Peak (~600% above baseline)** | 12-hour run + design flaw + Insights triggered |
| Feb 7–9 | Elevated | Design flaw active on normal-length runs |
| Feb 9–10 | Near baseline | — |
| **Feb 11–13** | **High (~2nd largest spike)** | Design flaw + Insights triggered again |
| Feb 14–16 | Near baseline | — |
| Feb 17 | Slightly elevated | Next scheduled run |

---

## What Has Been Fixed

The code defect — the unnecessary per-resource database call — **has been remediated as of February 17, 2026.**

The fix adds a result cache so each account is looked up exactly once per run, regardless of how many non-compliant resources it contains. This reduces the excess API call volume by an estimated **50–200× per run** and will prevent the recurring elevated cost pattern on future scheduled runs.

No functionality was changed — the job produces identical reports. Only the number of redundant API calls was eliminated.

---

## What Remains Open

| Item | Priority | Action Required |
|---|---|---|
| Investigate why the Feb 5–6 run lasted ~12 hours | High | Review ECS task logs; add a maximum runtime limit so the job cannot run indefinitely |
| Review CloudTrail Insights configuration | High | Confirm with security/compliance team whether Insights is required; disabling it eliminates the secondary cost component entirely |
| Audit both active CloudTrail trails for event overlap | Medium | Verify the two trails are not recording the same events twice — the second copy of any event is fully paid |

---

## Business Impact Summary

| Dimension | Assessment |
|---|---|
| Cost impact | High — ~600% peak spike, recurring elevated cost through Feb 17 |
| Security impact | None — CloudTrail logging functioned correctly throughout |
| Compliance impact | None — no data loss, no rule misconfiguration |
| Operational impact | Low — automation job produced correct output; only efficiency was affected |
| Recurrence risk | **Reduced** — primary code fix applied Feb 17; residual risk from open items above |

---

*Prepared: February 17, 2026 | Detailed technical RCA: `CloudTrail_Cost_Spike_RCA.md`*

