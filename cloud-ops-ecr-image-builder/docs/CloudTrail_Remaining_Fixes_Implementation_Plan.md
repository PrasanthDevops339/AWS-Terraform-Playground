# CloudTrail Cost Spike — Remaining Fixes Implementation Plan

> **Status**: Primary fix (`check_account()` caching) applied Feb 17, 2026 ✅
> **This Document**: Implementation plan for 3 remaining critical fixes

---

## Summary of Issues

| Issue | Status | Priority | Est. Cost Impact |
|-------|--------|----------|------------------|
| `check_account()` uncached | ✅ **FIXED** | Critical | 50-200× reduction achieved |
| **ECS task timeout missing** | ⚠️ **OPEN** | **Critical** | 12-hour run = 12× cost multiplier |
| **CloudTrail Insights enabled** | ⚠️ **OPEN** | **High** | $0.35 per 100k events + compounding |
| **Trail overlap (double recording)** | ⚠️ **OPEN** | **High** | 2× cost if both trails record same events |
| `get_rule_description()` API calls | ⚠️ **OPEN** | Medium | Addressed by DynamoDB cache (optional) |
| boto3 clients in loops | ⚠️ **OPEN** | Low | Minor overhead |

---

## Fix 1: ECS Task Timeout (CRITICAL - Prevents 12-Hour Runaway)

### Problem
The Feb 5–6 ECS task ran for **~12 hours** instead of completing normally. No timeout was configured, allowing it to run indefinitely.

**Cost Impact**: 12-hour runtime = **12× normal API call volume** = ~600% cost spike

### Solution A: Add ECS Task-Level Timeout (Infrastructure)

#### For ECS Task Definition (Fargate or EC2):

**File**: Terraform or CloudFormation defining the ECS task

```hcl
# Terraform example
resource "aws_ecs_task_definition" "config_aggregator" {
  family = "config-aggregator-task"

  container_definitions = jsonencode([{
    name  = "config-aggregator"
    image = "your-ecr-repo/config-aggregator:latest"

    # Add hard stop timeout (seconds)
    stopTimeout = 120  # 2 minutes for graceful shutdown

    # Add health check to detect stuck tasks
    healthCheck = {
      command     = ["CMD-SHELL", "ps aux | grep python || exit 1"]
      interval    = 60
      timeout     = 5
      retries     = 3
      startPeriod = 120
    }
  }])

  # Set task execution timeout via task role policy
  task_role_arn = aws_iam_role.config_aggregator_task_role.arn
}
```

#### For EventBridge Scheduled Task:

Add a CloudWatch alarm to detect long-running tasks:

```hcl
resource "aws_cloudwatch_metric_alarm" "config_aggregator_long_running" {
  alarm_name          = "config-aggregator-task-timeout"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TaskDuration"
  namespace           = "ECS/ContainerInsights"
  period              = 7200  # 2 hours
  statistic           = "Maximum"
  threshold           = 7200  # Alert if task runs longer than 2 hours
  alarm_description   = "Config aggregator task exceeded expected runtime"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.config_aggregator.name
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
}
```

**Add Lambda to auto-stop long-running tasks:**

```python
# Lambda triggered by CloudWatch alarm
import boto3

def lambda_handler(event, context):
    ecs = boto3.client('ecs')

    # List running tasks for this service
    response = ecs.list_tasks(
        cluster='your-cluster-name',
        serviceName='config-aggregator-service',
        desiredStatus='RUNNING'
    )

    # Stop all running tasks
    for task_arn in response['taskArns']:
        ecs.stop_task(
            cluster='your-cluster-name',
            task=task_arn,
            reason='Task exceeded maximum runtime - auto-terminated by CloudWatch alarm'
        )

    return {'statusCode': 200, 'body': f'Stopped {len(response["taskArns"])} tasks'}
```

---

### Solution B: Add Script-Level Timeout (Code Change)

**File**: [config_aggregator.py:391](../scripts/config_aggregator.py#L391)

Add a watchdog timer that forcibly exits after maximum allowed runtime:

```python
# Add at top of file after imports (line 50)
import signal
from datetime import datetime, timedelta

# Configuration
MAX_RUNTIME_HOURS = 2  # Maximum 2 hours
TASK_START_TIME = datetime.now()

def check_runtime_timeout():
    """Check if task has exceeded maximum runtime"""
    elapsed = datetime.now() - TASK_START_TIME
    if elapsed > timedelta(hours=MAX_RUNTIME_HOURS):
        logger.error(f"Task exceeded maximum runtime of {MAX_RUNTIME_HOURS} hours")
        logger.error(f"Elapsed time: {elapsed}")
        logger.error("Forcibly exiting to prevent runaway cost")
        sys.exit(1)

# Alternative: Signal-based timeout (Unix/Linux only)
def _timeout_handler(signum, frame):
    logger.error(f"Task exceeded maximum allowed runtime of {MAX_RUNTIME_HOURS} hours")
    logger.error("SIGALRM timeout triggered - exiting")
    raise SystemExit(1)

# Set alarm for 2 hours (7200 seconds)
signal.signal(signal.SIGALRM, _timeout_handler)
signal.alarm(MAX_RUNTIME_HOURS * 3600)
```

**Add timeout check in main loop** (line 447, inside the `for item in results:` loop):

```python
# Inside main processing loop, add periodic check
for item in results:
    # Check timeout every 100 resources
    if results.index(item) % 100 == 0:
        check_runtime_timeout()

    parsed_results = json.loads(item)
    # ... rest of processing
```

**Benefits**:
- Guarantees task stops after 2 hours (or configured limit)
- Logs clear error message for investigation
- Prevents 12× cost multiplier scenarios

**Risk**: None - Task already produces output incrementally to S3, so partial results are preserved

---

## Fix 2: Disable CloudTrail Insights (HIGH PRIORITY - Eliminate Compounding Charges)

### Problem
CloudTrail Insights is enabled and triggering anomaly detection charges (`USE2-InsightsEvents`) on high-volume runs.

**Cost Structure**:
1. Pay for `PaidEventsRecorded` (base management events)
2. Pay AGAIN for `InsightsEvents` when volume is abnormal ($0.35 per 100k events)

**Compounding Effect**: Feb 5 and Feb 11-13 show BOTH charges simultaneously

### Investigation Step 1: Check Which Trails Have Insights Enabled

```bash
# Check both active trails
aws cloudtrail get-insight-selectors --trail-name aws-controltower-BaselineCloudTrail --region us-east-2

aws cloudtrail get-insight-selectors --trail-name aws-aft-CustomizationsCloudTrail --region us-east-2
```

**Expected output if enabled**:
```json
{
  "TrailARN": "arn:aws:cloudtrail:us-east-2:...:trail/aws-controltower-BaselineCloudTrail",
  "InsightSelectors": [
    {
      "InsightType": "ApiCallRateInsight"
    }
  ]
}
```

### Investigation Step 2: Determine If Insights Is Required

**Questions to ask Security/Compliance team**:
- Is CloudTrail Insights a compliance requirement?
- Are Insights alerts being actively monitored?
- Have Insights events led to actionable security findings?

**If NO to all three** → Disable Insights immediately

### Remediation: Disable CloudTrail Insights

#### Option A: AWS Console
1. Navigate to CloudTrail → Trails
2. Select trail (e.g., `aws-controltower-BaselineCloudTrail`)
3. Click "Insights events"
4. Uncheck "Enable Insights"
5. Save changes

#### Option B: AWS CLI
```bash
# Disable Insights on Control Tower trail
aws cloudtrail put-insight-selectors \
  --trail-name aws-controltower-BaselineCloudTrail \
  --region us-east-2 \
  --insight-selectors '[]'

# Disable Insights on AFT trail
aws cloudtrail put-insight-selectors \
  --trail-name aws-aft-CustomizationsCloudTrail \
  --region us-east-2 \
  --insight-selectors '[]'
```

#### Option C: Terraform (if trails are managed via IaC)

```hcl
resource "aws_cloudtrail" "baseline" {
  name                          = "aws-controltower-BaselineCloudTrail"
  s3_bucket_name                = var.cloudtrail_bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true

  # REMOVE or set to empty list
  # insight_selector {
  #   insight_type = "ApiCallRateInsight"
  # }
}
```

### Verification

After disabling, wait 24-48 hours and check Cost Explorer:
- `USE2-InsightsEvents` should drop to $0
- `USE2-PaidEventsRecorded` should continue to decrease (from other fixes)

**Expected Savings**: Eliminates **entire secondary cost component** (Insights charges)

---

## Fix 3: Audit Trail Overlap (Prevent Double-Recording)

### Problem
Two organization-wide, multi-region trails are active:
1. `aws-controltower-BaselineCloudTrail`
2. `aws-aft-CustomizationsCloudTrail`

**If both trails record the same management events** → You're paying twice:
- First copy: FREE (AWS gives 1 free copy per region)
- Second copy: **100% PAID**

### Investigation: Compare Trail Configurations

```bash
# Get detailed configuration for both trails
aws cloudtrail get-trail --name aws-controltower-BaselineCloudTrail --region us-east-2 > baseline_trail.json

aws cloudtrail get-trail --name aws-aft-CustomizationsCloudTrail --region us-east-2 > aft_trail.json

# Check event selectors (what events are logged)
aws cloudtrail get-event-selectors --trail-name aws-controltower-BaselineCloudTrail --region us-east-2 > baseline_events.json

aws cloudtrail get-event-selectors --trail-name aws-aft-CustomizationsCloudTrail --region us-east-2 > aft_events.json
```

### Check for Overlap

Compare the `EventSelectors` in both outputs. Look for:

```json
{
  "EventSelectors": [
    {
      "ReadWriteType": "All",  // If BOTH trails have "All", you're double-recording
      "IncludeManagementEvents": true,  // If BOTH are true, you're double-recording
      "DataResources": []
    }
  ]
}
```

**Overlap Scenarios**:

| Baseline Trail | AFT Trail | Result |
|----------------|-----------|--------|
| ReadWriteType: All | ReadWriteType: All | ❌ **Full overlap** - 100% double-recording |
| Management: true | Management: true | ❌ **Full overlap** - 100% double-recording |
| ReadWriteType: All | ReadWriteType: WriteOnly | ⚠️ **Partial overlap** - Write events doubled |
| Management: true | Management: false | ✅ No overlap for management events |

### Remediation Options

#### Option A: Keep Control Tower Trail Only for Management Events (Recommended)

**Rationale**: Control Tower trails are AWS-managed and required for Control Tower operation.

```bash
# Keep baseline trail as-is (logs everything)
# Modify AFT trail to exclude management events

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

**Result**: AFT trail now only logs data events (S3, Lambda), not management events.

#### Option B: Scope AFT Trail to Write-Only Events

```bash
# AFT trail only logs Write operations (creates, updates, deletes)
# Baseline trail logs everything

aws cloudtrail put-event-selectors \
  --trail-name aws-aft-CustomizationsCloudTrail \
  --region us-east-2 \
  --event-selectors '[
    {
      "ReadWriteType": "WriteOnly",
      "IncludeManagementEvents": true,
      "DataResources": []
    }
  ]'
```

**Result**: Baseline logs Read+Write, AFT only logs Write → Read events not duplicated.

#### Option C: Delete or Disable AFT Trail (If Not Required)

**Check with AFT team first!** If the AFT trail is not required for operational or compliance needs:

```bash
# Stop logging (keeps trail definition but stops recording)
aws cloudtrail stop-logging --name aws-aft-CustomizationsCloudTrail --region us-east-2

# OR delete entirely
aws cloudtrail delete-trail --name aws-aft-CustomizationsCloudTrail --region us-east-2
```

### Verification

After changes, monitor Cost Explorer for 3-5 days:
- If overlap existed, `USE2-PaidEventsRecorded` should drop by ~50%
- First copy is free, second copy was 100% paid → removing second copy = 50% total reduction

---

## Fix 4: Move boto3 Clients Outside Loops (LOW PRIORITY - Minor Optimization)

### Problem
boto3 clients are created inside hot-path loops:

**Line 234** - `get_rule_description()`:
```python
def get_rule_description(rule_name, account_id, region, rule_ann):
    client = boto3.client('config', region_name=REGION, config=Config(retries={'max_attempts': 10}))
    # ... function continues
```

**Line 555** - S3 upload loop:
```python
for group_keys, group_df in grouped_data:
    # ... processing
    s3 = boto3.client('s3', region_name=REGION)  # Created every iteration
    s3.put_object(...)
```

**Cost Impact**: Minor - may trigger extra `sts:AssumeRole` calls if role chaining is in use.

### Remediation

**Create clients once at module level** (after line 85):

```python
# After SUSPENDED_OU_ID definition (line 84)
# Create shared clients at module level
_config_client = None
_s3_client = None

def get_config_client():
    """Get or create cached Config client"""
    global _config_client
    if _config_client is None:
        _config_client = boto3.client('config', region_name=REGION,
                                      config=Config(retries={'max_attempts': 10}))
    return _config_client

def get_s3_client():
    """Get or create cached S3 client"""
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client('s3', region_name=REGION)
    return _s3_client
```

**Update `get_rule_description()` (line 234)**:
```python
def get_rule_description(rule_name, account_id, region, rule_ann):
    client = get_config_client()  # Use cached client
    # ... rest of function
```

**Update S3 upload loop (line 555)**:
```python
s3 = get_s3_client()  # Move BEFORE the loop, not inside

for group_keys, group_df in grouped_data:
    # ... processing
    s3.put_object(...)  # Use the shared client
```

---

## Fix 5: Optimize `get_rule_description()` API Calls (MEDIUM PRIORITY)

### Problem
`get_rule_description()` makes paginated Config API calls for each unique (rule, account, region).

**Current behavior**:
- 50 accounts × 2 rules × 3 regions = 300 potential API calls per run
- Each call may paginate 5-10 times
- Total: **1,500-3,000 Config API calls per run**

### Remediation Option A: Implement DynamoDB Cache (Recommended)

See [SPECIFIC_RECOMMENDATIONS.md](SPECIFIC_RECOMMENDATIONS.md) lines 97-172 for full implementation.

**Summary**:
1. Create DynamoDB table: `operations-{env}-annotation-cache`
2. Add TTL field (7-day expiration)
3. Load cache at script start
4. Save annotations after fetching
5. Subsequent runs: 80-95% cache hit rate

**Cost Savings**:
- First run: Same cost (cache warming)
- Subsequent runs: 1,500 → 150 API calls (90% reduction)

### Remediation Option B: Increase PageSize (Quick Win)

**File**: [config_aggregator.py:241](../scripts/config_aggregator.py#L241)

```python
# Current (default PageSize = 50)
detail_iterator = detail_paginator.paginate(
    ConfigurationAggregatorName=AGGREGATOR_NAME,
    ConfigRuleName=rule_name,
    AccountId=account_id,
    AwsRegion=region,
    ComplianceType='NON_COMPLIANT'
)

# Optimized (PageSize = 100)
detail_iterator = detail_paginator.paginate(
    ConfigurationAggregatorName=AGGREGATOR_NAME,
    ConfigRuleName=rule_name,
    AccountId=account_id,
    AwsRegion=region,
    ComplianceType='NON_COMPLIANT',
    PaginationConfig={
        'PageSize': 100  # Max allowed by AWS API
    }
)
```

**Cost Savings**: 50% reduction in pagination API calls (5 pages → 2.5 pages per lookup)

---

## Implementation Priority & Timeline

### Week 1: Critical Fixes (Must-Do)

| Fix | Priority | Effort | Owner | Deadline |
|-----|----------|--------|-------|----------|
| Add ECS task timeout (Solution A + B) | **Critical** | 4 hours | DevOps + Dev | End of Week 1 |
| Disable CloudTrail Insights | **High** | 30 minutes | Security team approval + DevOps | End of Week 1 |
| Audit trail overlap | **High** | 2 hours | DevOps | End of Week 1 |

**Expected Cost Reduction**: 70-90% from baseline (combined with existing `check_account()` fix)

### Week 2: Optimization Fixes (High Value)

| Fix | Priority | Effort | Owner | Deadline |
|-----|----------|--------|-------|----------|
| PageSize increase | Medium | 5 minutes | Dev | Week 2 |
| Move boto3 clients outside loops | Low | 30 minutes | Dev | Week 2 |

**Expected Additional Savings**: 10-20%

### Week 3+: Advanced Optimization (Optional)

| Fix | Priority | Effort | Owner | Deadline |
|-----|----------|--------|-------|----------|
| DynamoDB annotation cache | Medium | 3-4 hours | Dev | Week 3 |

**Expected Additional Savings**: 40-50% (mostly on subsequent runs)

---

## Validation & Monitoring

### Post-Implementation Checklist

After each fix, validate in Cost Explorer:

- [ ] **Day 1 after timeout fix**: Verify no ECS tasks exceed 2-hour runtime
- [ ] **Day 2 after Insights disabled**: Check `USE2-InsightsEvents` drops to $0
- [ ] **Day 3 after trail overlap fix**: Monitor `USE2-PaidEventsRecorded` baseline
- [ ] **Day 7**: Compare total CloudTrail costs to pre-fix baseline
- [ ] **Day 30**: Confirm sustained cost reduction

### CloudWatch Alarms to Add

```hcl
# Alert if CloudTrail costs spike again
resource "aws_cloudwatch_metric_alarm" "cloudtrail_cost_spike" {
  alarm_name          = "cloudtrail-cost-anomaly"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400  # Daily
  statistic           = "Maximum"
  threshold           = 20.00  # $20/day threshold (adjust based on baseline)
  alarm_description   = "CloudTrail costs exceeded expected baseline"

  dimensions = {
    ServiceName = "AWSCloudTrail"
    Currency    = "USD"
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
}
```

### Success Metrics

| Metric | Before Fixes | After Week 1 | After Week 3 |
|--------|--------------|--------------|--------------|
| CloudTrail daily cost | $50-100 (baseline) → $600-700 (spike) | Target: $30-50 | Target: $15-25 |
| ECS task duration | 12 hours (worst case) | Max 2 hours (hard limit) | Max 2 hours |
| Config API calls per run | ~5,000-10,000 | Target: ~2,500-5,000 | Target: ~500-1,000 |
| DynamoDB Query calls per run | 5,000 (fixed ✅) | ~50-100 | ~50-100 |

---

## Risk Assessment

| Fix | Risk Level | Rollback Plan |
|-----|------------|---------------|
| ECS timeout | Low | Remove timeout if legitimate long runs are detected |
| Disable Insights | Low | Re-enable via CLI in 5 minutes if required |
| Trail overlap fix | Medium | Revert event selectors via CLI; test in non-prod first |
| boto3 client caching | None | Pure optimization, no functional change |
| PageSize increase | None | Pure optimization, no functional change |

---

## Cost Impact Projection

### Current State (Post `check_account()` Fix)
- **Daily cost**: ~$30-50 on normal runs, ~$500-700 on anomaly runs
- **Monthly**: ~$900-1,500

### After Week 1 Fixes
- **Daily cost**: ~$10-20
- **Monthly**: ~$300-600
- **Savings**: 60-70% reduction

### After All Fixes (Week 3)
- **Daily cost**: ~$5-10
- **Monthly**: ~$150-300
- **Savings**: 80-90% reduction from current state

---

## Summary Table

| Fix | Status | Priority | Cost Impact | Effort | Risk |
|-----|--------|----------|-------------|--------|------|
| `check_account()` cache | ✅ Done | Critical | 50-200× reduction | — | None |
| **ECS timeout** | ⚠️ Open | **Critical** | Prevents 12× multiplier | 4 hrs | Low |
| **Disable Insights** | ⚠️ Open | **High** | Eliminates compounding charges | 30 min | Low |
| **Trail overlap** | ⚠️ Open | **High** | Potential 50% reduction | 2 hrs | Medium |
| PageSize increase | ⚠️ Open | Medium | 50% pagination reduction | 5 min | None |
| boto3 client caching | ⚠️ Open | Low | Minor STS call reduction | 30 min | None |
| DynamoDB annotation cache | ⚠️ Open | Medium | 80-90% on subsequent runs | 4 hrs | None |

---

*Implementation Plan Created: February 24, 2026*
*Cross-reference: `CloudTrail_Cost_Spike_RCA.md` for detailed analysis*
