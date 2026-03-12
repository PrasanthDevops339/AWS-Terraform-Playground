# config_aggregator.py — API Metrics & Call Analysis

## Overview

The script queries AWS Config aggregator for non-compliant resources across multiple accounts.
It tracks API usage via the `api_metrics` dictionary for cost monitoring and optimization validation.

---

## API Calls Made

### 1. `select_aggregate_resource_config` (AWS Config)

| Property | Detail |
|---|---|
| **AWS API** | `config:SelectAggregateResourceConfig` |
| **File location** | `config_aggregator.py`, lines 186–198 |
| **Metric key** | `api_metrics['config_query_calls']` |
| **Page size** | 100 (maximum allowed by AWS) |

**What it does:**
Runs a SQL query against the Config aggregator to find all `NON_COMPLIANT` resources matching a resource ID prefix (e.g. `vol-`, `i-`, `sg-`). Each call fetches one page of results. When AWS returns a `NextToken`, the loop calls the API again for the next page.

**What drives the call count (e.g. 404 calls):**
```
Number of rules × Number of resource type prefixes × Number of result pages
```

**Does adding more accounts increase this number?**
No. The aggregator spans all accounts and returns results from all of them in a single query. More accounts means more results per page, not more API calls. The only things that increase this number are:
- More rules added to `POLICY_TABLE`
- More resource type prefixes per rule (`res_types`)
- So many NON_COMPLIANT resources that results overflow into additional pages

---

### 2. `get_aggregate_compliance_details_by_config_rule` (AWS Config)

| Property | Detail |
|---|---|
| **AWS API** | `config:GetAggregateComplianceDetailsByConfigRule` |
| **File location** | `config_aggregator.py`, lines 270–283 |
| **Metric key** | `api_metrics['rule_description_calls']` |
| **Page size** | 100 (maximum allowed by AWS — upgraded from default 50) |

**What it does:**
For each non-compliant resource, fetches the **annotation text** — the human-readable description of why the resource is non-compliant — for a specific `(rule_name, account_id, region)` combination.

**Does adding more accounts increase this number?**
Yes. These calls are per `(rule_name, account_id, region)` combination. More accounts = more unique combinations = more cache misses on the first run.

---

## Annotation Cache

### How It Works

Every call to `get_rule_description()` first checks the in-memory `annotation_cache` dict before making an API call:

```python
cache_key = (rule_name, account_id, region)

if cache_key in annotation_cache:
    api_metrics['rule_description_cache_hits'] += 1
    return annotation_cache[cache_key]  # No API call made
```

### Why It Matters

The script processes results in a deeply nested loop:

```
For each rule
  └── For each resource type prefix (vol-, i-, sg-, eni-...)
        └── For each NON_COMPLIANT resource result
              └── For each config rule on that resource
                    └── get_rule_description(rule_name, account_id, region)
```

A single account in a single region may have **thousands of non-compliant resources** all violating the same rule. Every one of those calls `get_rule_description()` with the exact same `(rule_name, account_id, region)` key:

- **First resource** → cache miss → real API call → result stored in `annotation_cache`
- **2nd through Nth resource** → cache hit → return immediately, no API call

### Metrics Breakdown

#### Previous Run (limited scope)

| Metric | Value |
|---|---|
| Config Query API Calls | 404 |
| Rule Description API Calls | 17 |
| Rule Description Cache Hits | 10,835 |
| Rule Description Wildcard Skips | 0 |
| **Total Config API Calls** | **421** |
| **Cache Hit Rate** | **99.8%** |

#### Full Production Run

| Metric | Value |
|---|---|
| Config Query API Calls | 8,311 |
| Rule Description API Calls | 1,073 |
| Rule Description Cache Hits | 226,133 |
| Rule Description Wildcard Skips | 0 |
| **Total Config API Calls** | **9,384** |
| **Cache Hit Rate** | **99.5%** |

**Key observations from the full run:**
- Config query calls jumped from 404 → 8,311 (~20x), indicating a much larger number of rules × resource type prefixes × result pages being processed across all accounts
- Rule description calls went from 17 → 1,073, reflecting more unique `(rule, account, region)` combinations across the full account set
- Cache hits went from 10,835 → 226,133, showing each unique combination was reused on average ~211 times
- Cache hit rate held strong at 99.5%, confirming the cache is working effectively at scale — without it, total API calls would have been ~227,206 instead of 9,384

---

## Page Size Limits

Both APIs are already set to their **maximum allowed page size of 100**. This cannot be increased further via AWS APIs.

```python
# get_aggregate_compliance_details_by_config_rule
PaginationConfig={
    'PageSize': 100  # Max allowed by AWS (default was 50)
}
```

To further reduce API calls, consider:

| Approach | Targets |
|---|---|
| Pre-warm cache at startup | Rule description calls |
| Persist cache in DynamoDB/ElastiCache across runs | Rule description calls |
| Consolidate SQL queries across resource prefixes | Config query calls |
| Reduce number of enabled rules | Both |

---

## Wildcard Annotation Shortcut

If a rule's annotation filter contains `"*"`, the script skips the API call entirely:

```python
if "*" in rule_ann:
    annotation_cache[cache_key] = "NON_COMPLIANT (wildcard match)"
    api_metrics['rule_description_wildcard_skips'] += 1
    return annotation_cache[cache_key]
```

This is tracked separately as `rule_description_wildcard_skips` and counts toward the cache hit rate calculation.
