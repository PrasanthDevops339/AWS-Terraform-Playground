# CloudTrail Cost Spike — RCA & Action Plan

> **Incident**: February 5–17, 2026 | **Peak increase**: ~600% | **Script**: `config_aggregator.py`

---

## What Happened

CloudTrail costs spiked 600% driven by two cost components:
- `USE2-PaidEventsRecorded` — management events beyond the free first-copy baseline
- `USE2-InsightsEvents` — anomaly detection charges triggered by abnormally high API volumes

| Period | Relative Cost | Cause |
|--------|---------------|-------|
| Feb 1–3 | Baseline | Normal |
| **Feb 5–6** | **~600% peak** | 12-hour ECS run + uncached DynamoDB calls + Insights triggered |
| Feb 7–9 | Elevated | Uncached calls on every normal run |
| **Feb 11–13** | **High** | Insights triggered again |
| Feb 17 | Slightly elevated | Last run before fix |

---

## Root Causes

### RC1 — `check_account()` called once per resource, not once per account ✅ FIXED Feb 17

Every non-compliant resource triggered a DynamoDB `Query` call. With 5,000 resources across 50 accounts this was **5,000 calls per run** instead of 50. Every call is a paid CloudTrail management event.

**Fix applied**:
```python
# Added version_cache dict and check_account_cached() wrapper
version_cache = {}

def check_account_cached(account_name):
    if account_name not in version_cache:
        version_cache[account_name] = check_account(account_name)
    return version_cache[account_name]

# Call site changed from:
is_one_dot_zero = check_account(account_name)
# To:
is_one_dot_zero = check_account_cached(account_name)
```

**Reduction**: 5,000 DynamoDB calls → 50 per run (100× fewer).

---

### RC2 — ECS task ran ~12 hours on Feb 5–6 ⚠️ OPEN

No task timeout was configured. A 12-hour run produces 12× the normal API volume — directly caused the peak spike. Root cause of the long run is still under investigation (throttling retries, large result set, or paginator stall).

---

### RC3 — CloudTrail Insights enabled ⚠️ OPEN

Insights fires when API call rates are abnormally high. Because of RC1+RC2, the call volume triggered Insights on Feb 5 and Feb 11–13, creating a compounding charge: pay once for the events, pay again for Insights detecting the anomaly.

---

### RC4 — Possible trail overlap (double-recording) ⚠️ OPEN

Two org-wide multi-region trails are active. If both record the same management events, the second copy is 100% paid.

- `aws-controltower-BaselineCloudTrail`
- `aws-aft-CustomizationsCloudTrail`

---

## Remaining Fixes (Copy-Paste Ready)

### Fix 1 — Add ECS Task Timeout ⚠️ CRITICAL

Prevents another 12-hour runaway. Two layers recommended.

#### A — Script-level watchdog (add to `config_aggregator.py`)

```python
# ADD at top of file after imports
import signal

def _timeout_handler(signum, frame):
    logger.error("Task exceeded maximum allowed runtime of 2 hours. Exiting.")
    raise SystemExit(1)

# ADD inside if __name__ == '__main__': block, before processing starts
signal.signal(signal.SIGALRM, _timeout_handler)
signal.alarm(7200)  # 2 hours = 7200 seconds
```

#### B — ECS task definition (Terraform)

```hcl
resource "aws_ecs_task_definition" "config_aggregator" {
  family = "config-aggregator-task"

  container_definitions = jsonencode([{
    name        = "config-aggregator"
    image       = "your-ecr-repo/config-aggregator:latest"
    stopTimeout = 120  # 2-minute graceful shutdown window
  }])
}
```

#### C — CloudWatch alarm to alert on long-running tasks

```hcl
resource "aws_cloudwatch_metric_alarm" "config_aggregator_timeout" {
  alarm_name          = "config-aggregator-task-timeout"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 7200   # check every 2 hours
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Config aggregator still running after 2 hours"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]

  dimensions = {
    ClusterName = "your-cluster-name"
    ServiceName = "config-aggregator-service"
  }
}
```

---

### Fix 2 — Disable CloudTrail Insights ⚠️ HIGH

Eliminates the `USE2-InsightsEvents` cost component entirely. Check with security team first.

#### Check which trails have Insights enabled

```bash
aws cloudtrail get-insight-selectors \
  --trail-name aws-controltower-BaselineCloudTrail \
  --region us-east-2

aws cloudtrail get-insight-selectors \
  --trail-name aws-aft-CustomizationsCloudTrail \
  --region us-east-2
```

If output contains `"InsightType": "ApiCallRateInsight"` → Insights is enabled.

#### Disable Insights

```bash
# Disable on Control Tower trail
aws cloudtrail put-insight-selectors \
  --trail-name aws-controltower-BaselineCloudTrail \
  --region us-east-2 \
  --insight-selectors '[]'

# Disable on AFT trail
aws cloudtrail put-insight-selectors \
  --trail-name aws-aft-CustomizationsCloudTrail \
  --region us-east-2 \
  --insight-selectors '[]'
```

**Savings**: Removes entire `USE2-InsightsEvents` cost line — $300-600/month.

---

### Fix 3 — Audit Trail Overlap ⚠️ HIGH

If both trails record Read+Write management events, one is fully redundant and 100% paid.

#### Check event selectors on both trails

```bash
aws cloudtrail get-event-selectors \
  --trail-name aws-controltower-BaselineCloudTrail \
  --region us-east-2

aws cloudtrail get-event-selectors \
  --trail-name aws-aft-CustomizationsCloudTrail \
  --region us-east-2
```

If both return `"IncludeManagementEvents": true` + `"ReadWriteType": "All"` → full overlap.

#### Fix: Disable management events on AFT trail

```bash
aws cloudtrail put-event-selectors \
  --trail-name aws-aft-CustomizationsCloudTrail \
  --region us-east-2 \
  --event-selectors '[
    {
      "ReadWriteType": "All",
      "IncludeManagementEvents": false,
      "DataResources": []
    }
  ]'
```

**Savings**: Up to 50% reduction in `USE2-PaidEventsRecorded` if full overlap existed.

---

### Fix 4 — Investigate Feb 5–6 12-Hour Runtime ⚠️ MEDIUM

Run this Athena query against CloudTrail S3 logs to identify which API calls dominated:

```sql
SELECT
    useridentity.arn,
    eventsource,
    eventname,
    COUNT(*) AS event_count
FROM cloudtrail_logs
WHERE
    eventtime >= '2026-02-05T00:00:00Z'
    AND eventtime <= '2026-02-06T23:59:59Z'
GROUP BY useridentity.arn, eventsource, eventname
ORDER BY event_count DESC
LIMIT 50;
```

Cross-reference with ECS task CloudWatch logs to identify whether the delay was in:
- Config aggregator query pagination (large result set)
- `get_rule_description()` paginator stalling on a rule/account/region
- `ThrottlingException` retries (`time.sleep(3 * tries)` can stall up to 9 seconds per call)

---

## Status Summary

| Fix | Priority | Status | Expected Savings |
|-----|----------|--------|-----------------|
| RC1: `check_account()` cache | Critical | ✅ Done Feb 17 | $300-600/month |
| Fix 1: ECS timeout | Critical | ⚠️ Open | Prevents 12× spike recurrence |
| Fix 2: Disable Insights | High | ⚠️ Open | $300-600/month |
| Fix 3: Trail overlap | High | ⚠️ Open | up to $450/month |
| Fix 4: Investigate 12hr run | Medium | ⚠️ Open | Preventative |

## Cost Projection

| State | Monthly Cost | vs Baseline |
|-------|--------------|-------------|
| Baseline (Feb 1–3) | ~$90-150 | — |
| During spike (Feb 5–17) | ~$900-1,500 | +600% |
| After RC1 fix only ✅ | ~$450-900 | -40% |
| After all fixes | ~$90-200 | Back to baseline |
