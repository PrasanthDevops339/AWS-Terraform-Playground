# AWS Config Aggregator - Cost Optimization Summary

> **Document Purpose**: Executive summary of cost issues, root causes, and cost savings analysis
> **Date**: February 24, 2026
> **Affected Script**: `config_aggregator.py`

---

## Executive Summary

The `config_aggregator.py` compliance automation script was causing excessive AWS costs through two primary issues:

1. **CloudTrail Cost Spike** - 600% increase in CloudTrail logging costs
2. **AWS Config API Overuse** - Thousands of unnecessary API calls per execution

**Total Cost Impact**: $900-1,500/month → Can be reduced to $150-300/month (80-90% savings)

---

## Issue 1: CloudTrail Cost Spike (600% Increase)

### What Happened

**Period**: February 5-17, 2026
**Cost Increase**: Approximately **600% above baseline**
**Root Cause**: Uncached database lookups + 12-hour runaway task + CloudTrail Insights charges

### The Problem in Detail

#### Problem 1A: Uncached `check_account()` Function ✅ FIXED

**Location**: `config_aggregator.py` line 302 (original), line 487 (call site)

**Issue**:
```python
# BEFORE (BAD)
for item in results:  # Loop through 5,000 resources
    account_name = get_account_name_cached(account_id)  # Cached ✓
    is_one_dot_zero = check_account(account_name)  # NOT CACHED ✗
    # ... processing
```

**What This Caused**:
- Script processes 5,000 non-compliant resources
- `check_account()` makes 1 DynamoDB Query per resource
- **5,000 DynamoDB API calls** instead of 50 (one per unique account)
- Every DynamoDB Query is a CloudTrail management event
- **5,000 paid CloudTrail events per run**

**Math**:
```
5,000 resources across 50 accounts
Without cache: 5,000 DynamoDB calls
With cache:       50 DynamoDB calls
Reduction: 99% (100× fewer calls)
```

#### Problem 1B: No ECS Task Timeout ⚠️ OPEN

**Issue**: ECS task ran for ~12 hours on Feb 5-6 instead of normal 1-2 hours

**What This Caused**:
- 12-hour runtime = 12× the API call volume
- Normal run: ~500 API calls
- 12-hour run: ~6,000 API calls
- **12× cost multiplier** on that day

**Why It Happened**:
- No `stopTimeout` configured in ECS task definition
- No script-level timeout guard
- No CloudWatch alarm for long-running tasks

#### Problem 1C: CloudTrail Insights Enabled ⚠️ OPEN

**Issue**: CloudTrail Insights anomaly detection was triggering on high API volumes

**Cost Structure**:
1. Pay for base management events (`USE2-PaidEventsRecorded`)
2. Pay AGAIN when Insights detects anomaly (`USE2-InsightsEvents`)
3. **Compounding charge effect**

**Cost Explorer Evidence**:
- Feb 5-6: Both `PaidEventsRecorded` AND `InsightsEvents` charged
- Feb 11-13: Both components charged again
- **Double billing on high-volume days**

#### Problem 1D: Possible Trail Overlap ⚠️ OPEN

**Issue**: Two organization-wide CloudTrail trails are active:
1. `aws-controltower-BaselineCloudTrail`
2. `aws-aft-CustomizationsCloudTrail`

**If both record the same management events**:
- First copy: FREE (AWS gives 1 free copy)
- Second copy: **100% PAID**
- **Potential 50% cost increase from duplication**

---

### CloudTrail Cost - Before Fix

| Component | Daily Cost | Monthly Cost | Notes |
|-----------|------------|--------------|-------|
| Baseline (Feb 1-3) | $3-5 | $90-150 | Normal operation |
| **Peak Spike (Feb 5-6)** | **$50-70** | **N/A** | 12-hour run |
| Elevated (Feb 7-13) | $15-30 | $450-900 | Recurring uncached calls |
| Insights charges | $5-15 | $150-450 | Triggered on high-volume days |
| **Total (Feb 1-17)** | **Avg $30-50** | **$900-1,500** | — |

**Cost Breakdown by Driver**:
```
USE2-PaidEventsRecorded:  $600-900/month (60-70%)
USE2-InsightsEvents:      $300-600/month (30-40%)
```

---

### CloudTrail Cost - After Fixes

#### After Fix 1A Only (`check_account()` cache) ✅ APPLIED FEB 17

**Immediate Impact**:
- DynamoDB calls: 5,000 → 50 per run (99% reduction)
- CloudTrail events: -4,950 per run
- Estimated savings: **40-50% reduction**

| Component | Daily Cost | Monthly Cost | Savings |
|-----------|------------|--------------|---------|
| PaidEventsRecorded | $15-25 | $450-750 | 40% reduction |
| InsightsEvents | $10-20 | $300-600 | Still triggering occasionally |
| **Total** | **$25-45** | **$750-1,350** | **$150-150/month saved** |

#### After All CloudTrail Fixes (Week 1 - 3 Additional Fixes)

**Fixes Applied**:
1. ✅ `check_account()` cache (done)
2. ⚠️ ECS timeout (2-hour limit)
3. ⚠️ Disable CloudTrail Insights
4. ⚠️ Fix trail overlap (if exists)

| Component | Daily Cost | Monthly Cost | Savings vs Baseline |
|-----------|------------|--------------|---------------------|
| PaidEventsRecorded | $5-10 | $150-300 | 75% reduction |
| InsightsEvents | $0 | $0 | 100% reduction (disabled) |
| Trail overlap eliminated | — | — | 50% reduction (if was overlapping) |
| **Total** | **$5-10** | **$150-300** | **$750-1,200/month saved (80-90%)** |

---

## Issue 2: AWS Config API Overuse

### The Problem in Detail

#### Problem 2A: `get_rule_description()` - Excessive Pagination

**Location**: `config_aggregator.py` lines 233-265

**Issue**:
```python
def get_rule_description(rule_name, account_id, region, rule_ann):
    client = boto3.client('config', ...)  # New client every call

    detail_iterator = detail_paginator.paginate(
        ConfigurationAggregatorName=AGGREGATOR_NAME,
        ConfigRuleName=rule_name,
        AccountId=account_id,
        AwsRegion=region,
        ComplianceType='NON_COMPLIANT'
        # No PageSize limit - defaults to 50/page
        # No MaxItems limit - fetches ALL results
    )
```

**What This Caused**:
- Called for each unique (rule, account, region) combination
- 50 accounts × 2 rules × 3 regions = 300 unique combinations
- Each call paginates through evaluation results
- Average 5 pages per combination
- **1,500 Config API calls per run**

**Cost Impact**:
- AWS Config API: $0.001 per call
- 1,500 calls/day × 30 days = 45,000 calls/month
- **~$45/month in Config API costs**
- Each call is ALSO a CloudTrail management event
- Additional **~$15/month in CloudTrail costs**

#### Problem 2B: Annotation Lookup Has No Cross-Run Cache

**Issue**: Annotations are fetched every single run, even though they rarely change

**Example**:
- Rule: "backuptags"
- Account: 123456789012
- Region: us-east-2
- Annotation: "Resource has backup tag keys are missing: Name, Owner"

**This annotation text doesn't change**, but we fetch it on:
- Day 1 run: 1 API call
- Day 2 run: 1 API call (same annotation)
- Day 3 run: 1 API call (same annotation)
- ...
- Day 30 run: 1 API call (same annotation)

**Total**: 30 API calls to get the same unchanging string

---

### AWS Config API Cost - Before Fix

**Current State** (Item 1 rule only):

| Operation | Calls per Run | Calls per Month | Monthly Cost |
|-----------|---------------|-----------------|--------------|
| Initial Config query | 1-2 | 30-60 | $0.03-0.06 |
| Rule descriptions (uncached) | 250-500 | 7,500-15,000 | $7.50-15.00 |
| **Total Config API** | **252-502** | **7,530-15,060** | **$7.53-15.06** |

**CloudTrail Impact from Config APIs**:
- 15,000 Config API calls = 15,000 CloudTrail events
- ~$15-20/month additional CloudTrail costs

**Total Cost (Config + CloudTrail)**: **~$22-35/month**

---

### AWS Config API Cost - After Optimizations

#### After Optimization Phase 1 (PageSize: 100) - 5 Minutes Effort

**Changes**:
```python
detail_iterator = detail_paginator.paginate(
    ConfigurationAggregatorName=AGGREGATOR_NAME,
    ConfigRuleName=rule_name,
    AccountId=account_id,
    AwsRegion=region,
    ComplianceType='NON_COMPLIANT',
    PaginationConfig={
        'PageSize': 100  # Was 50, now 100 (max allowed)
    }
)
```

**Impact**:
- Pagination calls: 5 pages → 2.5 pages per lookup
- Total API calls: 502 → 252 per run
- **50% reduction in Config API costs**

| Operation | Calls per Run | Calls per Month | Monthly Cost | Savings |
|-----------|---------------|-----------------|--------------|---------|
| Initial Config query | 1-2 | 30-60 | $0.03-0.06 | — |
| Rule descriptions | 125-250 | 3,750-7,500 | $3.75-7.50 | 50% ↓ |
| **Total** | **127-252** | **3,780-7,560** | **$3.78-7.56** | **$3.75-7.50/mo saved** |

Plus CloudTrail savings: ~$7-10/month
**Total Savings**: ~$11-17/month

---

#### After Optimization Phase 2 (DynamoDB Cache) - 3 Hours Effort

**Changes**:
1. Create DynamoDB cache table: `operations-{env}-annotation-cache`
2. Load cache at script start
3. Save annotations to cache after fetching
4. 7-day TTL on cached items

**Impact - First Run**:
- Same as Phase 1 (252 API calls)
- Cache warming: All 100 annotations saved to DynamoDB

**Impact - Subsequent Runs**:
- Cache hit rate: 90-95% (annotations rarely change)
- API calls: 252 → 25 per run (90% cache hits)
- **90% reduction in Config API costs** (after first run)

| Operation | First Run | Subsequent Runs (Avg) | Monthly Cost | Savings |
|-----------|-----------|------------------------|--------------|---------|
| Initial Config query | 1-2 | 1-2 | $0.06 | — |
| Rule descriptions (cache miss) | 250 | 25 | $0.75 | 90% ↓ |
| DynamoDB cache reads | 0 | 100 | $0.0003 | — |
| DynamoDB cache writes | 100 | 10 | $0.0001 | — |
| **Total** | **$7.50** | **$0.76** | **~$1.00-2.00/month** | **$20-33/mo saved** |

Plus CloudTrail savings: ~$18-28/month
**Total Savings**: ~$38-61/month

---

## Combined Cost Analysis (Both Issues)

### Current State (Before Any Fixes)

| Cost Category | Monthly Cost | Notes |
|---------------|--------------|-------|
| CloudTrail - PaidEventsRecorded | $600-900 | Uncached DynamoDB calls + Config APIs |
| CloudTrail - InsightsEvents | $300-600 | Anomaly detection charges |
| AWS Config APIs | $7-15 | Rule description lookups |
| **Total** | **$907-1,515** | — |

---

### After `check_account()` Cache Only (Applied Feb 17) ✅

| Cost Category | Monthly Cost | Savings | % Reduction |
|---------------|--------------|---------|-------------|
| CloudTrail - PaidEventsRecorded | $300-600 | $300-300 | 50% |
| CloudTrail - InsightsEvents | $300-600 | $0 | 0% (still triggering) |
| AWS Config APIs | $7-15 | $0 | 0% |
| **Total** | **$607-1,215** | **$300/mo** | **33%** |

---

### After Week 1 Fixes (CloudTrail Focus)

**Fixes Applied**:
1. ✅ `check_account()` cache
2. ⚠️ ECS 2-hour timeout
3. ⚠️ Disable CloudTrail Insights
4. ⚠️ Fix trail overlap (if exists)
5. ⚠️ PageSize: 100

| Cost Category | Monthly Cost | Savings | % Reduction |
|---------------|--------------|---------|-------------|
| CloudTrail - PaidEventsRecorded | $150-300 | $450-600 | 75% |
| CloudTrail - InsightsEvents | $0 | $300-600 | 100% (disabled) |
| AWS Config APIs | $4-8 | $3-7 | 50% |
| **Total** | **$154-308** | **$753-1,207/mo** | **83%** |

---

### After All Optimizations (Week 3)

**Fixes Applied**:
1. ✅ All Week 1 fixes
2. ⚠️ DynamoDB annotation cache
3. ⚠️ Wildcard annotation shortcut
4. ⚠️ boto3 client caching

| Cost Category | Monthly Cost | Savings vs Baseline | % Reduction |
|---------------|--------------|---------------------|-------------|
| CloudTrail - PaidEventsRecorded | $100-200 | $500-700 | 83% |
| CloudTrail - InsightsEvents | $0 | $300-600 | 100% |
| AWS Config APIs | $1-2 | $6-13 | 90% |
| DynamoDB cache costs | $0.01 | — | — |
| **Total** | **$101-202** | **$806-1,313/mo** | **89%** |

---

## Summary Table: Before & After

| Scenario | Monthly Cost | Annual Cost | Savings vs Baseline |
|----------|--------------|-------------|---------------------|
| **BEFORE (Feb 1-17, 2026)** | **$900-1,500** | **$10,800-18,000** | — |
| After `check_account()` fix ✅ | $600-1,200 | $7,200-14,400 | $3,600/year (33%) |
| **After Week 1 fixes (Recommended)** | **$150-300** | **$1,800-3,600** | **$9,000-14,400/year (80-83%)** |
| After all optimizations (Week 3) | $100-200 | $1,200-2,400 | $9,600-15,600/year (89%) |

---

## Implementation Effort vs Savings

| Fix | Effort | Monthly Savings | Annual Savings | ROI |
|-----|--------|-----------------|----------------|-----|
| `check_account()` cache ✅ | 30 min | $300 | $3,600 | Immediate |
| ECS timeout | 4 hours | $200-300 | $2,400-3,600 | Immediate |
| Disable CloudTrail Insights | 30 min | $300-600 | $3,600-7,200 | Immediate |
| Trail overlap audit | 2 hours | $150-300 (if overlapping) | $1,800-3,600 | Immediate |
| PageSize: 100 | 5 min | $10-20 | $120-240 | Immediate |
| boto3 client caching | 30 min | $5-10 | $60-120 | Immediate |
| DynamoDB annotation cache | 3 hours | $40-60 | $480-720 | 1 month |
| **Total** | **10.5 hours** | **$1,005-1,590** | **$12,060-19,080** | **1 week payback** |

---

## What Has Been Fixed ✅

| Fix | Date Applied | Status | Impact |
|-----|--------------|--------|--------|
| `check_account()` caching | Feb 17, 2026 | ✅ **DEPLOYED** | 50% CloudTrail cost reduction |

---

## What Remains Open ⚠️

| Fix | Priority | Effort | Savings | Deadline |
|-----|----------|--------|---------|----------|
| ECS task timeout | **CRITICAL** | 4 hours | $200-300/mo | Week 1 |
| Disable CloudTrail Insights | **HIGH** | 30 min | $300-600/mo | Week 1 |
| Trail overlap audit | **HIGH** | 2 hours | $150-300/mo | Week 1 |
| PageSize: 100 | Medium | 5 min | $10-20/mo | Week 1 |
| boto3 client caching | Low | 30 min | $5-10/mo | Week 2 |
| DynamoDB annotation cache | Medium | 3 hours | $40-60/mo | Week 3 |

---

## Risk Assessment

| Risk | Without Fixes | After Week 1 Fixes | Notes |
|------|---------------|--------------------| ------|
| **Runaway cost spike** | **HIGH** | **LOW** | ECS timeout prevents 12× multipliers |
| Ongoing elevated costs | High | Low | Insights disabled + caching reduces baseline |
| CloudTrail compliance | None | None | All fixes maintain full audit trail |
| Functional impact | None | None | Output CSV remains identical |

---

## Recommendation

### Immediate Action (Week 1)

**Priority**: All CloudTrail fixes

**Why**:
- Prevents another 600% spike if task runs long again
- Eliminates compounding Insights charges
- Achieves 80-83% total cost reduction
- Effort: 7 hours total

**Expected Outcome**:
- Monthly cost: $900-1,500 → $150-300
- Annual savings: **$9,000-14,400**
- **Pays for itself in 1 week of engineering time**

### Follow-Up (Week 2-3)

**Priority**: Config API optimizations

**Why**:
- Incremental 10-20% additional savings
- Reduces CloudTrail event volume further
- Sets up for future rule additions

**Expected Outcome**:
- Monthly cost: $150-300 → $100-200
- Annual savings: **Additional $600-1,200**

---

## Monitoring & Validation

### Success Metrics (Track in AWS Cost Explorer)

| Metric | Baseline | Week 1 Target | Week 3 Target |
|--------|----------|---------------|---------------|
| Daily CloudTrail cost | $30-50 | $5-10 | $3-7 |
| Monthly CloudTrail cost | $900-1,500 | $150-300 | $90-210 |
| CloudTrail `PaidEventsRecorded` | $600-900 | $150-300 | $90-200 |
| CloudTrail `InsightsEvents` | $300-600 | $0 | $0 |
| ECS task max duration | 12 hours (worst) | 2 hours (max) | 2 hours (max) |
| Config API calls per run | 500-1,000 | 250-500 | 25-50 |

---

## Reference Documents

| Document | Purpose |
|----------|---------|
| [CloudTrail_Cost_Spike_RCA.md](CloudTrail_Cost_Spike_RCA.md) | Detailed technical root cause analysis |
| [CloudTrail_Cost_Spike_Executive_Summary.md](CloudTrail_Cost_Spike_Executive_Summary.md) | Executive summary of CloudTrail issue |
| [CloudTrail_Remaining_Fixes_Implementation_Plan.md](CloudTrail_Remaining_Fixes_Implementation_Plan.md) | Step-by-step implementation guide |
| [OPTIMIZATION_PLAN.md](../scripts/OPTIMIZATION_PLAN.md) | Config API optimization strategies |
| [SPECIFIC_RECOMMENDATIONS.md](../scripts/SPECIFIC_RECOMMENDATIONS.md) | Recommendations based on actual DynamoDB rules |

---

**Document Owner**: Cloud Operations Team
**Last Updated**: February 24, 2026
**Next Review**: After Week 1 fixes deployment
