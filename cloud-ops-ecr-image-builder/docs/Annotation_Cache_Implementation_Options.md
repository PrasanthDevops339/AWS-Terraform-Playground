# Annotation Cache Implementation Options

> **Purpose**: Compare different approaches for caching AWS Config rule annotations across script executions
> **Decision Required**: Choose between DynamoDB, S3, or no cross-execution cache
> **Impact**: 80-90% API cost reduction on subsequent runs

---

## Executive Summary

| Approach | Setup Time | Ongoing Cost | API Savings | Recommendation |
|----------|------------|--------------|-------------|----------------|
| **Option A: DynamoDB** | 30 min + 3 hrs code | $0.01/month | 80-90% | ✅ **Recommended** |
| **Option B: S3** | 2 hrs code only | $0.001/month | 70-80% | ⚠️ Alternative |
| **Option C: No Cache** | 0 | $0 | 0% | ❌ Miss savings |

---

## The Problem

Currently, the script fetches annotation details for each (rule, account, region) combination **every single run**:

```
Day 1 run: Fetch annotation for ("backuptags", "123456789012", "us-east-2") → API call
Day 2 run: Fetch same annotation → API call (waste!)
Day 3 run: Fetch same annotation → API call (waste!)
...
Day 30 run: Fetch same annotation → API call (waste!)
```

**Current cost**: 250 API calls per run × 30 runs = **7,500 API calls/month**

**With cache**:
- Day 1: 250 API calls (cache warming)
- Days 2-30: ~25 API calls per run (90% cache hits)
- **Total: 250 + (29 × 25) = 975 API calls/month**
- **Savings: 87% reduction**

---

## Option A: DynamoDB Cache (Recommended)

### How It Works

```
┌─────────────┐
│ Script runs │
└──────┬──────┘
       │
       ├─1─→ Load cache from DynamoDB
       │    (read all cached annotations)
       │
       ├─2─→ Process resources
       │    └─→ Need annotation?
       │        ├─→ In cache? → Use it ✓
       │        └─→ Not in cache? → API call → Save to DynamoDB
       │
       └─3─→ Done (cache persists for 7 days)
```

### Implementation

#### Step 1: Create DynamoDB Table (30 minutes)

```bash
aws dynamodb create-table \
  --table-name operations-dev-annotation-cache \
  --attribute-definitions AttributeName=cache_key,AttributeType=S \
  --key-schema AttributeName=cache_key,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --time-to-live-specification "Enabled=true,AttributeName=ttl" \
  --region us-east-2 \
  --tags Key=Environment,Value=dev Key=Purpose,Value=annotation-cache
```

**Table Schema**:
```
Primary Key: cache_key (String)
Format: "backuptags#123456789012#us-east-2"

Attributes:
- cache_key: Primary key (composite of rule#account#region)
- rule_name: "backuptags"
- account_id: "123456789012"
- region: "us-east-2"
- annotation: "Resource has backup tag keys are missing: Name, Owner"
- ttl: 1740000000 (Unix timestamp - auto-delete after 7 days)
- updated_at: "2026-02-24T10:30:00Z"
```

#### Step 2: Add Environment Variable

```bash
# In your ECS task definition or Lambda environment
export ANNOTATION_CACHE_TABLE=operations-dev-annotation-cache
```

#### Step 3: Add Code (3 hours)

**A. Add cache loader function** (after line 230):
```python
def load_annotation_cache_from_dynamo():
    """Load previously cached annotations from DynamoDB"""
    cache_table_name = os.getenv('ANNOTATION_CACHE_TABLE')
    if not cache_table_name:
        logger.info("ANNOTATION_CACHE_TABLE not set - cross-run caching disabled")
        return {}

    try:
        dynamodb = boto3.resource('dynamodb', region_name=REGION)
        table = dynamodb.Table(cache_table_name)

        response = table.scan()
        loaded_cache = {}

        for item in response.get('Items', []):
            key = (item['rule_name'], item['account_id'], item['region'])
            loaded_cache[key] = item['annotation']

        logger.info(f"Loaded {len(loaded_cache)} annotations from DynamoDB cache")
        return loaded_cache
    except Exception as e:
        logger.warning(f"Could not load annotation cache from DynamoDB: {e}")
        return {}
```

**B. Add cache saver function**:
```python
def save_annotation_to_dynamo(rule_name, account_id, region, annotation):
    """Save annotation to DynamoDB with 7-day TTL"""
    cache_table_name = os.getenv('ANNOTATION_CACHE_TABLE')
    if not cache_table_name:
        return  # Silently skip if caching not configured

    try:
        dynamodb = boto3.resource('dynamodb', region_name=REGION)
        table = dynamodb.Table(cache_table_name)

        ttl = int(time.time()) + (7 * 24 * 60 * 60)  # 7 days

        table.put_item(Item={
            'cache_key': f"{rule_name}#{account_id}#{region}",
            'rule_name': rule_name,
            'account_id': account_id,
            'region': region,
            'annotation': annotation,
            'ttl': ttl,
            'updated_at': datetime.now().isoformat()
        })
    except Exception as e:
        logger.warning(f"Failed to cache annotation: {e}")
```

**C. Initialize cache at script start** (in `__main__` block, line 391):
```python
if __name__ == '__main__':
    tracer = trace.get_tracer(__name__)
    with tracer.start_as_current_span("GetConfig", kind=SpanKind.SERVER):
        # Load annotation cache from DynamoDB at start
        annotation_cache = load_annotation_cache_from_dynamo()

        # ... rest of script
```

**D. Save to cache when annotation found** (in `get_rule_description()`, after line 289):
```python
if ruleann_check:
    description = result['Annotation']
    logger.info(f"In subset desc {result['Annotation']}")
    annotation_cache[cache_key] = description
    save_annotation_to_dynamo(rule_name, account_id, region, description)  # ADD THIS
    return description
```

### Pros & Cons

| Aspect | Pro/Con | Details |
|--------|---------|---------|
| **Setup** | ❌ Con | Requires new DynamoDB table |
| **Code complexity** | ⚠️ Medium | ~50 lines of code |
| **Performance** | ✅ Pro | Fast item-level lookups |
| **TTL** | ✅ Pro | Automatic expiration (built-in) |
| **Concurrency** | ✅ Pro | Atomic operations, no conflicts |
| **Scalability** | ✅ Pro | Unlimited items |
| **Cost** | ✅ Pro | ~$0.01/month (negligible) |
| **Observability** | ✅ Pro | Can query cache contents easily |

### Cost Analysis

**DynamoDB Costs**:
```
Assumptions:
- 100 unique (rule, account, region) combinations
- 30 script runs per month
- First run: 100 writes, subsequent: 10 writes per run (new accounts)

Writes: 100 + (29 × 10) = 390 writes/month
Cost: 390 × $1.25 per million = $0.0005/month

Reads: 30 runs × 100 items = 3,000 reads/month
Cost: 3,000 × $0.25 per million = $0.0008/month

Storage: 100 items × 1KB = 100KB
Cost: Negligible (<$0.0001/month)

Total: ~$0.001-0.002/month (rounds to $0.01)
```

**API Savings**:
```
Before: 7,500 Config API calls/month × $0.001 = $7.50/month
After: 975 Config API calls/month × $0.001 = $0.98/month
Savings: $6.52/month

ROI: Save $6.52, pay $0.01 DynamoDB
Net savings: $6.51/month ($78/year)
```

---

## Option B: S3 Cache (Alternative)

### How It Works

```
┌─────────────┐
│ Script runs │
└──────┬──────┘
       │
       ├─1─→ Download annotation_cache.json from S3
       │    (parse entire file, filter expired entries)
       │
       ├─2─→ Process resources
       │    └─→ Need annotation?
       │        ├─→ In cache? → Use it ✓
       │        └─→ Not in cache? → API call → Add to memory
       │
       └─3─→ Upload annotation_cache.json to S3
            (overwrite entire file)
```

### Implementation

#### Step 1: Add Code (2 hours - no infrastructure setup!)

**A. Add S3 cache loader** (after line 230):
```python
import json

CACHE_S3_BUCKET = os.getenv('TAGGING_BUCKET')  # Reuse existing bucket
CACHE_S3_KEY = f'{bucket_prefix}/annotation_cache.json'

def load_annotation_cache_from_s3():
    """Load annotation cache from S3 JSON file"""
    if not CACHE_S3_BUCKET:
        return {}

    s3 = get_s3_client()
    try:
        response = s3.get_object(Bucket=CACHE_S3_BUCKET, Key=CACHE_S3_KEY)
        cache_data = json.loads(response['Body'].read().decode('utf-8'))

        # Filter out expired entries (manual TTL check)
        now = time.time()
        loaded_cache = {}
        expired_count = 0

        for key_str, item in cache_data.items():
            if item.get('ttl', 0) > now:  # Not expired
                key_parts = key_str.split('#')
                if len(key_parts) == 3:
                    key = (key_parts[0], key_parts[1], key_parts[2])
                    loaded_cache[key] = item['annotation']
            else:
                expired_count += 1

        logger.info(f"Loaded {len(loaded_cache)} annotations from S3 cache")
        logger.info(f"Filtered out {expired_count} expired entries")
        return loaded_cache

    except s3.exceptions.NoSuchKey:
        logger.info("No S3 cache found - starting fresh")
        return {}
    except Exception as e:
        logger.warning(f"Could not load annotation cache from S3: {e}")
        return {}
```

**B. Add S3 cache saver** (call at end of script, before line 590):
```python
def save_annotation_cache_to_s3():
    """Save annotation cache to S3 at end of run"""
    if not CACHE_S3_BUCKET:
        return

    s3 = get_s3_client()

    # Convert cache to serializable format
    cache_data = {}
    ttl = int(time.time()) + (7 * 24 * 60 * 60)  # 7 days from now

    for (rule_name, account_id, region), annotation in annotation_cache.items():
        key_str = f"{rule_name}#{account_id}#{region}"
        cache_data[key_str] = {
            'annotation': annotation,
            'ttl': ttl,
            'updated_at': datetime.now().isoformat()
        }

    try:
        s3.put_object(
            Bucket=CACHE_S3_BUCKET,
            Key=CACHE_S3_KEY,
            Body=json.dumps(cache_data, indent=2),
            ContentType='application/json'
        )
        logger.info(f"Saved {len(cache_data)} annotations to S3 cache")
    except Exception as e:
        logger.error(f"Failed to save annotation cache to S3: {e}")

# Call at end of script (before line 590):
save_annotation_cache_to_s3()
```

**C. Initialize at start** (line 391):
```python
if __name__ == '__main__':
    # Load annotation cache from S3 at start
    annotation_cache = load_annotation_cache_from_s3()
    # ... rest of script
```

### Pros & Cons

| Aspect | Pro/Con | Details |
|--------|---------|---------|
| **Setup** | ✅ Pro | No new resources needed |
| **Code complexity** | ⚠️ Medium | ~60 lines of code |
| **Performance** | ❌ Con | Slow (load/parse entire file) |
| **TTL** | ❌ Con | Manual implementation (filter on load) |
| **Concurrency** | ❌ Con | Last-write-wins (concurrent runs conflict) |
| **Scalability** | ⚠️ Limited | JSON file size limit (~5MB practical) |
| **Cost** | ✅ Pro | ~$0.001/month (cheaper than DynamoDB) |
| **Observability** | ✅ Pro | Easy to inspect (download JSON file) |

### Cost Analysis

**S3 Costs**:
```
Writes: 30 PUT requests/month
Cost: 30 × $0.005 per 1,000 = $0.00015/month

Reads: 30 GET requests/month
Cost: 30 × $0.0004 per 1,000 = $0.000012/month

Storage: 100KB file
Cost: 100KB × $0.023 per GB = $0.0000023/month

Total: ~$0.0002/month (rounds to $0.001)
```

**API Savings**: Same as DynamoDB (~$6.50/month)

### Limitations

1. **Concurrent runs**: If two ECS tasks run simultaneously, one will overwrite the other's cache
2. **File size limit**: Practical limit ~5MB (JSON parsing overhead)
3. **Slower startup**: Must download and parse entire file
4. **Manual TTL**: Need to filter expired entries on every load

---

## Option C: No Cross-Execution Cache (Current State)

### How It Works

```
┌─────────────┐
│ Script runs │
└──────┬──────┘
       │
       ├─1─→ annotation_cache = {} (empty)
       │
       ├─2─→ Process resources
       │    └─→ Need annotation? → API call every time
       │
       └─3─→ Done (cache discarded)

Next day: Start over from scratch
```

### Pros & Cons

| Aspect | Pro/Con | Details |
|--------|---------|---------|
| **Setup** | ✅ Pro | Already implemented |
| **Complexity** | ✅ Pro | No additional code |
| **Cost savings** | ❌ Con | 0% - no optimization |
| **API calls** | ❌ Con | 7,500/month instead of 975/month |
| **Monthly cost** | ❌ Con | $7.50 instead of $0.98 |

---

## Comparison Matrix

| Feature | DynamoDB | S3 | No Cache |
|---------|----------|----|----|
| **Setup time** | 30 min infra + 3 hrs code | 2 hrs code | 0 |
| **Infrastructure** | New table needed | Reuse existing bucket | None |
| **Monthly cost** | $0.01 | $0.001 | $0 |
| **API savings** | $6.50/month | $6.50/month | $0 |
| **Net savings** | $6.49/month | $6.50/month | $0 |
| **Annual savings** | $78 | $78 | $0 |
| **Cache hit rate** | 90-95% | 85-90% | N/A |
| **Startup time** | Fast (<1s) | Slow (2-5s) | Instant |
| **Concurrency safe** | ✅ Yes | ❌ No | ✅ Yes |
| **Auto TTL** | ✅ Yes | ❌ Manual | N/A |
| **Scalability** | ✅ Unlimited | ⚠️ Limited (5MB) | N/A |
| **Ease of debugging** | ✅ Query table | ✅ Download JSON | N/A |

---

## Decision Guide

### Choose DynamoDB if:
- ✅ You want the **proper, production-ready solution**
- ✅ You're okay with 30 minutes of infrastructure setup
- ✅ You value **concurrent-safety** (multiple ECS tasks)
- ✅ You want **automatic TTL** (set-and-forget)
- ✅ You anticipate **scaling** to 1,000+ cache entries

**→ This is the recommended approach**

### Choose S3 if:
- ⚠️ You cannot create a new DynamoDB table (permissions/policy)
- ⚠️ You only run **one instance at a time** (no concurrency)
- ⚠️ Cache will stay small (<500 entries)
- ⚠️ You're okay with manual TTL filtering
- ⚠️ You want to **avoid infrastructure changes**

**→ This is the workaround approach**

### Choose No Cache if:
- ❌ You're okay with **current API costs**
- ❌ You don't want to invest **any implementation time**
- ❌ API savings of $78/year aren't worth it

**→ Not recommended - missing out on easy savings**

---

## Implementation Recommendation

### Recommended Path: DynamoDB (Phased Rollout)

**Phase 1: Test Environment (Week 1)**
1. Create DynamoDB table in dev/test
2. Implement cache load/save functions
3. Run 5 test executions
4. Validate cache hit rate >85%
5. Compare CSV outputs (should be identical)

**Phase 2: Production (Week 2)**
1. Create DynamoDB table in prod
2. Deploy code changes
3. Monitor for 1 week
4. Validate cost reduction in Cost Explorer

**Rollback plan**: Remove env variable `ANNOTATION_CACHE_TABLE` - cache will be silently disabled

### Risk: LOW
- Falls back to API calls on any error
- No functionality changes
- Easy to disable (remove env variable)

---

## Testing Checklist

Before deploying to production:

- [ ] Test cache loading works (check logs for "Loaded X annotations")
- [ ] Test cache saving works (check DynamoDB table has items)
- [ ] Test cache hit (run twice, second run should show high cache hit rate)
- [ ] Test TTL works (check items have ttl attribute)
- [ ] Test empty cache scenario (delete table contents, verify script works)
- [ ] Test cache miss scenario (add new account, verify API call + cache save)
- [ ] Compare CSV output before/after (should be identical)
- [ ] Verify DynamoDB costs in Cost Explorer after 7 days

---

## Summary

| Metric | Current | With DynamoDB Cache | With S3 Cache |
|--------|---------|---------------------|---------------|
| API calls per run | 250 | 25 (90% cache hit) | 30 (85% cache hit) |
| Monthly API calls | 7,500 | 975 | 1,050 |
| Monthly API cost | $7.50 | $0.98 | $1.05 |
| Monthly cache cost | $0 | $0.01 | $0.001 |
| **Total monthly cost** | **$7.50** | **$0.99** | **$1.05** |
| **Monthly savings** | **—** | **$6.51 (87%)** | **$6.45 (86%)** |
| **Annual savings** | **—** | **$78** | **$77** |
| **ROI** | **—** | **3 hrs = $78/year** | **2 hrs = $77/year** |

**Recommendation**: Implement **DynamoDB cache** for proper, scalable solution.

---

**Next Steps**:
1. Review this document with team
2. Get approval for DynamoDB table creation
3. Implement Phase 1 (test environment)
4. Validate and deploy Phase 2 (production)

**Questions?** See full implementation code in [OPTIMIZATION_PLAN.md](../scripts/OPTIMIZATION_PLAN.md) lines 97-172
