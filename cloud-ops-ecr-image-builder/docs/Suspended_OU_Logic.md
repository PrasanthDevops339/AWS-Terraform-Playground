# Suspended OU Exclusion Logic

## Overview

The `config_aggregator.py` script queries AWS Config for non-compliant resources across all accounts in an AWS Organization. Accounts placed under the **Suspended OU** are decommissioned or inactive and must be excluded from compliance reporting. This document explains how that exclusion works, step by step, with sample accounts.

---

## What Is a Suspended OU?

In AWS Organizations, an **Organizational Unit (OU)** is a logical grouping of accounts. A **Suspended OU** is a dedicated OU where decommissioned, inactive, or retired accounts are moved. These accounts should not generate compliance reports because:

- They are no longer actively managed.
- Resources in those accounts are scheduled for cleanup or deletion.
- Reporting on them creates noise and wastes processing time.

The Suspended OU ID is hardcoded in the script:

```python
SUSPENDED_OU_ID = 'ou-susp345jkl'
```

---

## Sample Accounts

The following sample accounts illustrate how the logic applies:

| Account ID       | Account Name          | OU Location      | Suspended? | 1.0 (Legacy)? | Final Result           |
|------------------|-----------------------|-------------------|------------|----------------|------------------------|
| `111122223333`   | `prod-app-account`    | Production OU     | No         | No             | **Included** in report |
| `222233334444`   | `dev-test-account`    | Development OU    | No         | No             | **Included** in report |
| `333344445555`   | `legacy-finance`      | Production OU     | No         | Yes            | Excluded (1.0 legacy)  |
| `444455556666`   | `old-project`         | **Suspended OU**  | **Yes**    | No             | Excluded (Suspended)   |
| `555566667777`   | `decommissioned-app`  | **Suspended OU**  | **Yes**    | No             | Excluded (Suspended)   |
| `666677778888`   | `retired-legacy-app`  | **Suspended OU**  | **Yes**    | Yes            | Excluded (Suspended -- checked first) |

---

## How the Suspended OU Exclusion Works

### Step 1: Build a Cache of Suspended Account IDs

When the script first encounters a resource that requires a suspended-OU check, it calls `get_suspended_account_ids()`. This function:

1. Calls the AWS Organizations API (`list_accounts_for_parent`) with the Suspended OU ID.
2. Collects all account IDs **directly** under that OU (nested child OUs are not traversed).
3. Stores the result in a Python `set` (for O(1) lookup performance).
4. Caches the set with a timestamp so it is not re-fetched on every call.

```
Organizations API Call
      |
      v
Suspended OU (ou-susp345jkl)
  +-- 444455556666 (old-project)
  +-- 555566667777 (decommissioned-app)
  +-- 666677778888 (retired-legacy-app)
      |
      v
Cached Set: {444455556666, 555566667777, 666677778888}
```

**Cache behavior** is controlled by two environment variables:

| Variable                            | Default | Description                                      |
|-------------------------------------|---------|--------------------------------------------------|
| `SUSPENDED_OU_CACHE_TTL_ENABLED`    | `true`  | Whether the cache expires after a TTL period     |
| `SUSPENDED_OU_CACHE_TTL_SECONDS`    | `1800`  | How many seconds before the cache expires (30 min) |

If TTL is disabled, the cache persists for the lifetime of the process.

### Step 2: Per-Resource Check (Layer 1)

During the main processing loop, after fetching non-compliant resources from AWS Config, the script iterates over each resource. **Before** any other processing, it checks whether the resource's account is in the Suspended OU:

```python
# Line 394-396 in config_aggregator.py
if is_account_in_suspended_ou(account_id):
    logger.warning(f"[SUSPENDED OU] Skipping account: {account_id} ({account_name})")
    continue  # Skip this resource entirely
```

This is the **primary filter**. If the account is suspended, the resource is skipped immediately and never written to the in-memory CSV buffer.

### Step 3: CSV Upload Safety Check (Layer 2)

After all resources are processed and grouped by account, the script performs a **second check** before uploading each account's CSV to S3:

```python
# Lines 461-463 in config_aggregator.py
if is_account_in_suspended_ou(group_account_id):
    logger.warning(f"[SUSPENDED OU] Skipping CSV creation for suspended account: {group_account_id}")
    continue  # Do not create or upload CSV
```

This is a **safety net**. Even if a suspended account's resource somehow made it into the CSV buffer (e.g., due to a race condition or caching edge case), this check prevents the CSV file from being created and uploaded to S3.

---

## Two-Layer Defense Summary

| Layer   | Where in Code     | What It Prevents                               | Why It Exists                        |
|---------|-------------------|-------------------------------------------------|---------------------------------------|
| Layer 1 | Resource iteration (line 394) | Resources written to CSV buffer         | Primary filter -- fast, efficient     |
| Layer 2 | CSV upload (line 464)         | CSV file creation and S3 upload         | Safety net -- defense in depth        |

---

## Decision Flowchart

```
  Non-Compliant Resource from AWS Config
                |
                v
     Get account_id and account_name
                |
                v
  +-----------------------------+
  | Is account in Suspended OU? |
  +-----------------------------+
        |                |
       YES               NO
        |                |
        v                v
   SKIP resource    Get config rule annotations
   (log warning)         |
                         v
                +---------------------------+
                | Is account 1.0 (legacy)?  |
                +---------------------------+
                    |              |
                   YES             NO
                    |              |
                    v              v
               SKIP resource   Has matching annotations?
               (log: 1.0)        |              |
                                YES             NO
                                 |              |
                                 v              v
                          INCLUDE in CSV    SKIP resource
                          and upload to S3  (no annotations)
```

---

## Walkthrough: Sample Account Processing

### Account `444455556666` (old-project) -- Suspended

1. Resource `vol-0abc123def456` found as NON_COMPLIANT.
2. Account name resolved: `old-project`.
3. **Suspended OU check**: `444455556666` IS in the cached suspended set.
4. **Result**: Resource is skipped. Log output:
   ```
   [SUSPENDED OU] Skipping account: 444455556666 (old-project)
   ```
5. No CSV is written, no S3 upload occurs.

### Account `333344445555` (legacy-finance) -- 1.0 Legacy

1. Resource `vol-0xyz789abc123` found as NON_COMPLIANT.
2. Account name resolved: `legacy-finance`.
3. **Suspended OU check**: `333344445555` is NOT in the suspended set. Continue.
4. Config rule annotations retrieved.
5. **1.0 check**: DynamoDB query finds `legacy-finance` in the version table.
6. **Result**: Resource is skipped. Log output:
   ```
   Account 333344445555 & legacy-finance is 1.0 - skipping
   ```

### Account `111122223333` (prod-app-account) -- Included

1. Resource `vol-0def456ghi789` found as NON_COMPLIANT.
2. Account name resolved: `prod-app-account`.
3. **Suspended OU check**: `111122223333` is NOT in the suspended set. Continue.
4. Config rule annotations retrieved: `["Unencrypted volume"]`.
5. **1.0 check**: DynamoDB query does NOT find `prod-app-account`. Account is 2.0.
6. Annotations are present.
7. **Result**: Resource is written to CSV and uploaded to S3:
   ```
   CSV saved to s3://my-bucket/config-reports/111122223333-prod-app-account_1.csv
   ```

### Account `666677778888` (retired-legacy-app) -- Suspended AND 1.0

1. Resource found as NON_COMPLIANT.
2. Account name resolved: `retired-legacy-app`.
3. **Suspended OU check**: `666677778888` IS in the cached suspended set.
4. **Result**: Resource is skipped at the Suspended OU check. The DynamoDB (1.0) check is **never reached**.
   ```
   [SUSPENDED OU] Skipping account: 666677778888 (retired-legacy-app)
   ```

---

## Key Functions

| Function                           | Purpose                                              | Returns                     |
|------------------------------------|------------------------------------------------------|-----------------------------|
| `_list_accounts_for_parent()`      | Lists accounts directly under a given OU             | List of account ID strings  |
| `get_suspended_account_ids()`      | Fetches and caches suspended account IDs             | Set of account ID strings   |
| `is_account_in_suspended_ou()`     | Checks if a single account is in the Suspended OU    | `True` or `False`           |

---

## Important Notes

- **Only direct children**: The script only checks accounts directly under the Suspended OU. Accounts in nested child OUs within the Suspended OU are NOT excluded.
- **Error handling**: If the Organizations API call fails, the function returns an empty set, so no valid accounts are accidentally skipped.
- **Execution order**: The Suspended OU check runs before the DynamoDB 1.0 check. This is intentional -- the in-memory set lookup (O(1)) is faster than a DynamoDB network call, saving time and reducing costs.
- **Required IAM permission**: The script needs `organizations:ListAccountsForParent` to fetch accounts from the Suspended OU.
