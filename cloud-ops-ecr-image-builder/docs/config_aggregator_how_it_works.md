# config_aggregator.py — How It Works

> **Script location:** `scripts/config_aggregator.py`
> **Runtime:** AWS ECS (Fargate scheduled task)
> **Purpose:** Query AWS Config across all org accounts for non-compliant resources, filter and enrich the results, and upload per-account CSV reports to S3.

---

## 1. Overview

`config_aggregator.py` is a compliance reporting pipeline. It runs as a scheduled ECS task and produces one CSV file per AWS account containing all non-compliant resources for that account, enriched with rule annotation details and account metadata.

At a high level the script does five things in sequence:

```
DynamoDB (policy config)
        │
        ▼
AWS Config Aggregator  ──►  per-resource enrichment  ──►  in-memory CSV
        │                        │                              │
        │                   DynamoDB (version)            S3 (per account)
        │                   Organizations API
        │                   Config Annotation API
        ▼
   Result set (paginated)
```

---

## 2. Environment Variables

All configuration is injected via environment variables at ECS task launch time.

| Variable | Purpose | Example |
|---|---|---|
| `AGGREGATOR_NAME` | Name of the AWS Config multi-account aggregator | `org-config-aggregator` |
| `REGION` | AWS region for all API calls | `us-east-2` |
| `TAGGING_BUCKET` | S3 bucket where output CSVs are uploaded | `my-compliance-reports` |
| `BUCKET_PREFIX` | S3 key prefix for organising output files | `config-reports/daily` |
| `POLICY_TABLE` | DynamoDB table that holds the active policy/rule configuration | `operations-prod-policies` |
| `CLOUD_VERSION_TABLE` | DynamoDB table listing 1.0 (legacy) accounts to exclude | `operations-prod-cloud-versions` |
| `ACCOUNT_ID_ALLOWLIST` | Optional comma-separated list of account IDs to restrict the query scope | `111122223333,222233334444` |
| `SUSPENDED_OU_CACHE_TTL_ENABLED` | Whether the suspended OU cache expires (default `true`) | `true` |
| `SUSPENDED_OU_CACHE_TTL_SECONDS` | How long the suspended OU cache lives in seconds (default `1800`) | `1800` |

---

## 3. Script Entry Point and Startup

When the script is run directly (`__main__`), it:

1. Initialises an OpenTelemetry tracing span (`GetConfig`) for observability.
2. Queries the `POLICY_TABLE` DynamoDB table for the active ingest policy (rows where `source = 'aws_config'` and `enabled = True`).
3. Reads the policy's `ingest_policy` JSON field which contains:
   - `ResourceTypes` — list of resource ID prefixes to query (e.g. `vol-`, `i-`, `sg-`)
   - `Annotations` — annotation keyword filters for rule descriptions
   - `Rules` — config rule name filters
   - `ComplianceType` — compliance status to query (default `NON_COMPLIANT`)
4. Initialises an in-memory CSV buffer with the output field headers.
5. Iterates over each resource type prefix and calls `main(item)` to fetch results.

---

## 4. The `main()` Function — Config Aggregator Query

`main(item)` builds and executes a SQL query against the AWS Config aggregator.

### Query structure

```sql
SELECT
    resourceType, resourceId, resourceName,
    configuration.targetResourceType,
    configuration.complianceType,
    configuration.configRuleList,
    configurationItemCaptureTime,
    configurationItemStatus,
    accountId, awsRegion
WHERE configuration.complianceType = 'NON_COMPLIANT'
AND resourceId LIKE '<item>%'
[AND accountId IN ('<id1>', '<id2>', ...)]   -- only if ACCOUNT_ID_ALLOWLIST is set
ORDER BY accountId DESC
```

### Query variants

Two versions of the query exist in the code for different use cases:

| Version | When Active | Account Scope |
|---|---|---|
| **Production query** | Default (active) | All accounts, optionally filtered by `ACCOUNT_ID_ALLOWLIST` env var |
| **Test query** | Commented out — uncomment to activate | 12 hardcoded dummy account IDs for isolated testing |

**To switch to the test query for a test run:**
1. Comment out the `PRODUCTION QUERY` block (lines marked with `# TO TEST:`)
2. Uncomment the `TEST QUERY` block (lines marked with `# TO ACTIVATE:`)
3. Replace the dummy account IDs in the test query with real test account IDs
4. After testing, reverse the swap to restore production behaviour

### Pagination

The Config API returns results in pages. `main()` loops using `NextToken` until all pages are consumed, accumulating all results into a single list before returning.

### Retry logic

On `ThrottlingException`, the function retries up to 3 times with a linear backoff of `3 × attempt_number` seconds before raising.

---

## 5. Per-Resource Processing Loop

After `main()` returns, the script iterates over every resource in the result set and applies a multi-step filter chain before writing to CSV.

### Step-by-step per resource:

```
Resource from Config result
          │
          ▼
  ┌─────────────────────────┐
  │ Is account in Suspended │  YES → SKIP (log warning)
  │         OU?             │
  └─────────────────────────┘
          │ NO
          ▼
  Get account name (cached via account_cache)
          │
          ▼
  For each config rule violation on this resource:
    - Apply rule name filter (rule_type)
    - If rule matches: call get_rule_description() for annotation text
          │
          ▼
  ┌─────────────────────────┐
  │  Is account 1.0 legacy? │  YES → SKIP (log: 1.0 account)
  │  (cached DynamoDB check)│
  └─────────────────────────┘
          │ NO
          ▼
  ┌─────────────────────────┐
  │  Any matching           │  NO  → SKIP (log: no matching annotations)
  │  annotations found?     │
  └─────────────────────────┘
          │ YES
          ▼
  Write row to in-memory CSV buffer
```

---

## 6. Key Functions

### `main(item, tries=1)`
Executes the Config aggregator SQL query for a given resource ID prefix. Handles pagination and throttle retries. Returns a flat list of raw JSON strings.

### `get_rule_description(rule_name, account_id, region, rule_ann)`
Fetches the annotation text for a specific rule + account + region combination using the `GetAggregateComplianceDetailsByConfigRule` paginator.

- **Cache key:** `(rule_name, account_id, region)` stored in `annotation_cache`
- **Cache scope:** process lifetime (module-level dict)
- Returns the first annotation that matches the `rule_ann` keyword filter, or an empty string if none match.

### `get_account_name(account_id)`
Calls `organizations:DescribeAccount` to resolve an account ID to its human-readable name. No caching on the raw function.

### `get_account_name_cached(account_id)`
Wrapper around `get_account_name()` using the module-level `account_cache` dict. Ensures each account ID is resolved only once per run.

### `check_account(account_name)`
Queries the `CLOUD_VERSION_TABLE` DynamoDB table to determine whether an account is classified as 1.0 (legacy). Returns `True` if the account is found (1.0), `False` if not (2.0).

### `check_account_cached(account_name)` ✅ Added Feb 17, 2026
Wrapper around `check_account()` using the module-level `version_cache` dict. Ensures each account name is looked up in DynamoDB only once per run, regardless of how many resources it contains.

### `get_suspended_account_ids()`
Fetches all account IDs directly under the Suspended OU from AWS Organizations. Caches the result as a Python `set` for O(1) lookups. Cache TTL is controlled by `SUSPENDED_OU_CACHE_TTL_SECONDS` (default 30 minutes).

### `is_account_in_suspended_ou(account_id)`
Single-line O(1) membership check against the cached suspended account set. Returns `True` if the account should be excluded.

---

## 7. Caching Summary

The script maintains four in-process caches to avoid redundant API calls within a single run:

| Cache Variable | Function It Backs | Keyed By | API Call Avoided |
|---|---|---|---|
| `annotation_cache` | `get_rule_description()` | `(rule_name, account_id, region)` | `GetAggregateComplianceDetailsByConfigRule` |
| `account_cache` | `get_account_name_cached()` | `account_id` | `organizations:DescribeAccount` |
| `version_cache` | `check_account_cached()` | `account_name` | `dynamodb:Query` on version table |
| `suspended_account_cache` | `get_suspended_account_ids()` | N/A (full set) | `organizations:ListAccountsForParent` |

All four caches are module-level dicts/variables — they live for the lifetime of the ECS task process and are not shared across runs.

---

## 8. Account Exclusion Logic

Two separate exclusion checks prevent certain accounts from appearing in the output:

| Check | When It Runs | Source | Effect |
|---|---|---|---|
| Suspended OU check | Per resource, before any other processing | Organizations API (cached) | Resource skipped, no CSV row written |
| 1.0 legacy check | Per resource, after annotation retrieval | DynamoDB version table (cached) | Resource skipped, logged as 1.0 |

The Suspended OU check runs **first** — if an account is suspended, the DynamoDB check is never reached. This ordering is intentional: the in-memory set lookup (O(1)) is faster and free, while the DynamoDB call costs money.

A second Suspended OU check also runs at the S3 upload stage as a defence-in-depth safety net.

---

## 9. Output — CSV Format and S3 Upload

After all resources are processed, the in-memory CSV buffer is read into a pandas DataFrame and grouped by `(accountId, accountName)`. One CSV file is uploaded to S3 per unique account group.

### CSV columns

| Column | Source |
|---|---|
| `resourceId` | Config result |
| `resourceType` | Config result |
| `resourceName` | Config result |
| `targetResourceType` | Config result |
| `complianceType` | Config result |
| `configRuleName` | Config result (list of matching rule names) |
| `configurationItemCaptureTime` | Config result |
| `configurationItemStatus` | Config result |
| `accountId` | Config result |
| `accountName` | Organizations API (cached) |
| `awsRegion` | Config result |
| `description` | Config annotation API (cached) |

### S3 key format

```
{BUCKET_PREFIX}/{accountId}-{accountName}_{rule_id}.csv
```

Example: `config-reports/daily/111122223333-prod-app-account_1.csv`

---

## 10. Error Handling

| Scenario | Behaviour |
|---|---|
| `ThrottlingException` on Config query | Retry up to 3 times with `3 × attempt` second sleep |
| `ClientError` on DynamoDB query | Log error, return `False` (account treated as 2.0) |
| Organizations API failure (suspended OU) | Return empty set — no accounts accidentally excluded |
| Empty CSV buffer | `pd.errors.EmptyDataError` caught and logged |
| S3 upload failure | `ClientError` caught and logged per account |

---

## 11. IAM Permissions Required

The ECS task role must have the following permissions:

| Permission | Used By |
|---|---|
| `config:SelectAggregateResourceConfig` | `main()` — Config aggregator query |
| `config:GetAggregateComplianceDetailsByConfigRule` | `get_rule_description()` |
| `dynamodb:Query` | `check_account()` — version table lookup |
| `dynamodb:Query` | `__main__` — policy table lookup |
| `organizations:DescribeAccount` | `get_account_name()` |
| `organizations:ListAccountsForParent` | `get_suspended_account_ids()` |
| `s3:PutObject` | S3 CSV upload |
