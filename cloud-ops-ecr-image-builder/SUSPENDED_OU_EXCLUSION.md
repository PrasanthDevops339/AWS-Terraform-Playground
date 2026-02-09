# AWS Config Aggregator - Complete Script Documentation

This document explains the `scripts/config_aggregator.py` script, including the Suspended OU Exclusion feature and the 1.0/2.0 account version logic.

---

## Purpose

Queries AWS Config aggregator for **non-compliant resources** across multiple accounts, filters out:
1. Accounts in the **Suspended OU** (decommissioned accounts)
2. Accounts marked as **1.0** in DynamoDB (legacy accounts)

Then uploads compliance reports to S3, grouped by account.

---

## Example Accounts Used Throughout This Document

| Account ID | Account Name | OU Location | In DynamoDB (1.0)? | Result |
|------------|--------------|-------------|-------------------|--------|
| `111122223333` | `prod-app-account` | Production OU | No | ✅ **Included** in report |
| `222233334444` | `dev-test-account` | Development OU | No | ✅ **Included** in report |
| `333344445555` | `legacy-finance` | Production OU | **Yes** | ❌ Excluded (1.0 account) |
| `444455556666` | `old-project` | **Suspended OU** | No | ❌ Excluded (Suspended) |
| `555566667777` | `decommissioned-app` | **Suspended OU** | No | ❌ Excluded (Suspended) |
| `666677778888` | `retired-legacy-app` | **Suspended OU** | **Yes** | ❌ Excluded (Suspended - checked first) |

---

## FAQ: What Happens When Account Is In BOTH Suspended OU AND DynamoDB?

### Answer: Suspended OU Check Happens FIRST

If an account is in **both** the Suspended OU **and** the DynamoDB table (1.0), the **Suspended OU check wins** because it runs first in the code.

### Code Execution Order

```
┌────────────────────────────────────────────────────────────────────┐
│  Account: 666677778888 (retired-legacy-app)                        │
│  - In Suspended OU: YES                                            │
│  - In DynamoDB (1.0): YES                                          │
└────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────────────────┐
│  Line 394-396: FIRST CHECK - Suspended OU                          │
│                                                                    │
│  if is_account_in_suspended_ou(account_id):     ◄── Checked FIRST │
│      logger.warning("[SUSPENDED OU] Skipping...")                  │
│      continue  ◄── EXITS HERE, never reaches DynamoDB check       │
└────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
            ┌───────────────────┐
            │  SKIPPED ❌       │
            │  (Suspended OU)   │
            └───────────────────┘

            DynamoDB check (lines 416-428) is NEVER reached
```

### All Possible Scenarios

| Scenario | In Suspended OU? | In DynamoDB (1.0)? | What Happens | Log Message |
|----------|------------------|-------------------|--------------|-------------|
| Both flags | ✅ Yes | ✅ Yes | **Skipped at Suspended OU** (DynamoDB never queried) | `[SUSPENDED OU] Skipping account...` |
| Only Suspended | ✅ Yes | ❌ No | Skipped at Suspended OU check | `[SUSPENDED OU] Skipping account...` |
| Only 1.0 | ❌ No | ✅ Yes | Skipped at DynamoDB check | `Account ... is 1.0 - skipping` |
| Neither (with annotations) | ❌ No | ❌ No | ✅ **Included in report** | (no skip log, writes to CSV) |
| Neither (no annotations) | ❌ No | ❌ No | ❌ **Skipped** | `Account ... - skipped (no matching annotations)` |

### Why This Order?

This order is **intentional and efficient**:

1. **Suspended OU check** = O(1) in-memory set lookup (cached, no API call)
2. **DynamoDB check** = Network call to DynamoDB (slower)

By checking the cached Suspended OU first, we **avoid unnecessary DynamoDB queries** for suspended accounts, saving time and reducing DynamoDB costs.

### Log Output Example

For account `666677778888` (in both Suspended OU and DynamoDB):

```
[SUSPENDED OU] Skipping account: 666677778888 (retired-legacy-app)
```

You will **NOT** see the "1.0" log message because the `continue` statement exits the loop before reaching the DynamoDB check.

---

## Configuration

### Environment Variables

| Variable | Example Value | Description |
|----------|---------------|-------------|
| `AGGREGATOR_NAME` | `org-config-aggregator` | AWS Config aggregator name |
| `REGION` | `us-east-2` | AWS region |
| `TAGGING_BUCKET` | `my-compliance-bucket` | S3 bucket for results |
| `BUCKET_PREFIX` | `config-reports` | S3 key prefix |
| `POLICY_TABLE` | `operations-dev-policies` | DynamoDB policy table |
| `CLOUD_VERSION_TABLE` | `operations-dev-cloud-versions` | DynamoDB table for 1.0 accounts |
| `SUSPENDED_OU_CACHE_TTL_ENABLED` | `true` (default) | Enable/disable cache expiration |
| `SUSPENDED_OU_CACHE_TTL_SECONDS` | `1800` (default) | Cache TTL for suspended accounts (only if TTL enabled) |

### Cache TTL Configuration

The suspended account cache behavior is controlled by two environment variables:

| `SUSPENDED_OU_CACHE_TTL_ENABLED` | `SUSPENDED_OU_CACHE_TTL_SECONDS` | Behavior |
|----------------------------------|----------------------------------|----------|
| `true` (default) | `1800` (default) | Cache expires after 30 minutes, then refreshes from Organizations API |
| `true` | `3600` | Cache expires after 1 hour |
| `false` | (ignored) | Cache **never expires** - persists for entire container/process lifetime |

**When to disable TTL (`SUSPENDED_OU_CACHE_TTL_ENABLED=false`):**
- Suspended OU membership rarely changes
- You want to minimize Organizations API calls
- Container/task restarts frequently enough to refresh the cache

**Cache Logic Flow:**
```
┌─────────────────────────────────────────────────────────────────┐
│  get_suspended_account_ids() called                             │
├─────────────────────────────────────────────────────────────────┤
│  1. Is cache populated?                                         │
│     └─ No  → Fetch from Organizations API, cache it, return    │
│     └─ Yes → Continue to step 2                                │
│                                                                 │
│  2. Is SUSPENDED_OU_CACHE_TTL_ENABLED = false?                 │
│     └─ Yes → Return cached set (never expires)                 │
│     └─ No  → Continue to step 3                                │
│                                                                 │
│  3. Is cache age < SUSPENDED_OU_CACHE_TTL_SECONDS?             │
│     └─ Yes → Return cached set                                 │
│     └─ No  → Fetch from Organizations API, update cache        │
└─────────────────────────────────────────────────────────────────┘
```

### Hardcoded Configuration

```python
SUSPENDED_OU_ID = 'ou-susp345jkl'  # Update with your actual Suspended OU ID
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Organizations                            │
├─────────────────────────────────────────────────────────────────┤
│  Root                                                           │
│  ├── Production OU                                              │
│  │   ├── 111122223333 (prod-app-account)    → ✅ Included      │
│  │   └── 333344445555 (legacy-finance)      → ❌ 1.0 in DynamoDB│
│  ├── Development OU                                             │
│  │   └── 222233334444 (dev-test-account)    → ✅ Included      │
│  └── Suspended OU (ou-susp345jkl)                              │
│      ├── 444455556666 (old-project)         → ❌ Suspended     │
│      └── 555566667777 (decommissioned-app)  → ❌ Suspended     │
└─────────────────────────────────────────────────────────────────┘
```

> ⚠️ **Note:** Only accounts **directly under** the Suspended OU are excluded. Nested child OUs are NOT traversed.

---

## Complete Processing Flow (Step-by-Step)

### Step 1: Script Initialization

```
┌──────────────────────────────────────────────────────────────────┐
│  SCRIPT STARTS                                                   │
│  ├── Load environment variables                                  │
│  ├── Initialize OpenTelemetry tracer                            │
│  └── Query DynamoDB policy_table for enabled rules              │
└──────────────────────────────────────────────────────────────────┘
```

### Step 2: Query AWS Config Aggregator

```
┌──────────────────────────────────────────────────────────────────┐
│  For each resource type (e.g., 'vol-', 'i-', 'eni-'):           │
│  │                                                               │
│  │  Execute SQL Query:                                          │
│  │  SELECT resourceType, resourceId, accountId, ...             │
│  │  WHERE complianceType = 'NON_COMPLIANT'                      │
│  │  AND resourceId LIKE 'vol-%'                                 │
│  │                                                               │
│  └── Returns: List of non-compliant resources                   │
└──────────────────────────────────────────────────────────────────┘
```

### Step 3: Process Each Resource

For each non-compliant resource, the script runs through these checks:

```
┌──────────────────────────────────────────────────────────────────┐
│  RESOURCE: vol-0abc123def456 in account 444455556666            │
│                                                                  │
│  Step 3a: Get account name from Organizations API               │
│           444455556666 → "old-project"                          │
│                                                                  │
│  Step 3b: CHECK #1 - Is account in Suspended OU?                │
│           ┌─────────────────────────────────────────┐           │
│           │ is_account_in_suspended_ou(444455556666)│           │
│           │ → Checks against cached suspended set   │           │
│           │ → 444455556666 IS in suspended set      │           │
│           │ → Returns TRUE                          │           │
│           └─────────────────────────────────────────┘           │
│           Result: SKIP this resource ❌                         │
│           Log: "[SUSPENDED OU] Skipping account: 444455556666"  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  RESOURCE: vol-0xyz789abc123 in account 333344445555            │
│                                                                  │
│  Step 3a: Get account name                                      │
│           333344445555 → "legacy-finance"                       │
│                                                                  │
│  Step 3b: CHECK #1 - Is account in Suspended OU?                │
│           → 333344445555 NOT in suspended set                   │
│           → Returns FALSE                                        │
│           → Continue processing...                              │
│                                                                  │
│  Step 3c: Get config rule annotations                           │
│           → config_annotation = ["Missing encryption tag"]      │
│                                                                  │
│  Step 3d: CHECK #2 - Is account 1.0 or 2.0?                    │
│           ┌─────────────────────────────────────────┐           │
│           │ check_account("legacy-finance")         │           │
│           │ → Query DynamoDB: operations-dev-cloud-versions     │
│           │ → Key: account_name = "legacy-finance"  │           │
│           │ → FOUND in table                        │           │
│           │ → Returns TRUE (account is 1.0)         │           │
│           └─────────────────────────────────────────┘           │
│           Result: SKIP this resource ❌                         │
│           Log: "Account 333344445555 & legacy-finance is 1.0 - skipping" │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  RESOURCE: vol-0def456ghi789 in account 111122223333            │
│                                                                  │
│  Step 3a: Get account name                                      │
│           111122223333 → "prod-app-account"                     │
│                                                                  │
│  Step 3b: CHECK #1 - Is account in Suspended OU?                │
│           → 111122223333 NOT in suspended set                   │
│           → Returns FALSE → Continue...                         │
│                                                                  │
│  Step 3c: Get config rule annotations                           │
│           → config_annotation = ["Unencrypted volume"]          │
│                                                                  │
│  Step 3d: CHECK #2 - Is account 1.0 or 2.0?                    │
│           ┌─────────────────────────────────────────┐           │
│           │ check_account("prod-app-account")       │           │
│           │ → Query DynamoDB                        │           │
│           │ → NOT FOUND in table                    │           │
│           │ → Returns FALSE (account is 2.0)        │           │
│           └─────────────────────────────────────────┘           │
│           AND config_annotation is not empty                    │
│           Result: INCLUDE in report ✅                          │
│           → Write to CSV buffer                                 │
└──────────────────────────────────────────────────────────────────┘
```

### Step 4: Upload to S3 (with Safety Check)

```
┌──────────────────────────────────────────────────────────────────┐
│  Group CSV data by (accountId, accountName)                     │
│                                                                  │
│  For each account group:                                         │
│  ├── CHECK: Is account in Suspended OU? (Lines 461-463)        │
│  │   └── If YES → Skip CSV creation entirely ❌                 │
│  │   └── If NO → Continue to S3 upload                          │
│  │                                                               │
│  For account 111122223333 (prod-app-account):                   │
│  ├── Not in Suspended OU ✅                                     │
│  └── Upload to: s3://my-bucket/config-reports/                  │
│                 111122223333-prod-app-account_1.csv             │
│                                                                  │
│  For account 222233334444 (dev-test-account):                   │
│  ├── Not in Suspended OU ✅                                     │
│  └── Upload to: s3://my-bucket/config-reports/                  │
│                 222233334444-dev-test-account_1.csv             │
│                                                                  │
│  For account 444455556666 (old-project):                        │
│  ├── In Suspended OU ❌                                         │
│  ├── Log: "[SUSPENDED OU] Skipping CSV creation..."            │
│  └── NO CSV uploaded (safety net)                               │
└──────────────────────────────────────────────────────────────────┘
```

---

## Decision Logic Flowchart

```
                    ┌─────────────────────────┐
                    │  Non-Compliant Resource │
                    │  from AWS Config        │
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │  Get account_id &       │
                    │  account_name           │
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │  Is account in          │
                    │  Suspended OU?          │
                    └───────────┬─────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
                   YES                      NO
                    │                       │
                    ▼                       ▼
            ┌───────────────┐     ┌─────────────────────────┐
            │ SKIP ❌       │     │  Get config annotations │
            │ Log: Suspended│     └───────────┬─────────────┘
            └───────────────┘                 │
                                              ▼
                                ┌─────────────────────────┐
                                │  Is account in DynamoDB │
                                │  (1.0 account)?         │
                                └───────────┬─────────────┘
                                            │
                                ┌───────────┴───────────┐
                                │                       │
                               YES                      NO
                                │                       │
                                ▼                       ▼
                        ┌───────────────┐     ┌─────────────────────────┐
                        │ SKIP ❌       │     │  Has annotations?       │
                        │ Log: 1.0 acct │     └───────────┬─────────────┘
                        └───────────────┘                 │
                                              ┌───────────┴───────────┐
                                              │                       │
                                             YES                      NO
                                              │                       │
                                              ▼                       ▼
                                    ┌───────────────┐       ┌───────────────┐
                                    │ INCLUDE ✅    │       │ SKIP ❌       │
                                    │ Write to CSV  │       │ No annotation │
                                    └───────────────┘       └───────────────┘
```

---

## Two-Layer Defense: Suspended OU Exclusion

The script implements **two separate checks** for Suspended OU accounts to ensure no CSV files are ever created for suspended accounts:

### Layer 1: Per-Resource Check (Lines 394-396)

The first check happens during resource processing, **before writing to the in-memory CSV buffer**:

```python
if is_account_in_suspended_ou(account_id):
    logger.warning(f"[SUSPENDED OU] Skipping account: {account_id} ({account_name})")
    continue  # Skip this resource entirely
```

**Purpose:** Prevent suspended account resources from being written to the CSV buffer in the first place.

### Layer 2: CSV Upload Check (Lines 461-463)

The second check happens during S3 upload, **after grouping but before creating the CSV file**:

```python
# Extract account ID from group keys
if isinstance(group_keys, tuple):
    group_account_id = str(group_keys[0])
else:
    group_account_id = str(group_keys)

# Skip CSV creation for accounts in Suspended OU
if is_account_in_suspended_ou(group_account_id):
    logger.warning(f"[SUSPENDED OU] Skipping CSV creation for suspended account: {group_account_id}")
    continue  # Skip CSV creation and S3 upload
```

**Purpose:** Safety net to catch any suspended account resources that might slip through Layer 1 (e.g., due to race conditions, caching issues, or edge cases).

### Why Two Layers?

| Layer | When It Runs | What It Prevents | Why It's Needed |
|-------|--------------|------------------|-----------------|
| **Layer 1** (Per-Resource) | During resource iteration (early) | Resources written to CSV buffer | Primary filter - most efficient |
| **Layer 2** (CSV Upload) | Before S3 upload (late) | CSV file creation and S3 upload | Safety net - defense in depth |

**Result:** Even if Layer 1 misses a suspended account resource, Layer 2 ensures **no CSV file is ever uploaded to S3** for that account.

---

## Suspended OU Exclusion - Code Details

### Cache Variables (Lines 267-270)

```python
suspended_account_cache = None           # Stores set of suspended account IDs
suspended_account_cache_ts = None        # Timestamp when cache was refreshed
SUSPENDED_OU_CACHE_TTL_SECONDS = 1800    # Cache TTL (30 minutes default)
```

### Helper Function: `_list_accounts_for_parent()` (Lines 273-280)

Lists all accounts **directly under** a given OU (no nested traversal).

```python
def _list_accounts_for_parent(org_client, parent_id):
    # Uses paginator to handle large account lists
    # Returns: ['444455556666', '555566667777']
```

### Main Function: `get_suspended_account_ids()` (Lines 283-315)

```python
def get_suspended_account_ids():
    # 1. Check if cache is valid (not expired)
    #    └─ If valid → return cached set immediately
    #
    # 2. If cache expired:
    #    └─ Call _list_accounts_for_parent(SUSPENDED_OU_ID)
    #    └─ Returns accounts DIRECTLY under Suspended OU only
    #
    # 3. Cache the result with timestamp
    #
    # 4. Log: "[SUSPENDED OU] Cached 2 suspended accounts"
    #         "[SUSPENDED OU] Account IDs: 444455556666, 555566667777"
```

### Fast Lookup: `is_account_in_suspended_ou()` (Lines 317-323)

```python
def is_account_in_suspended_ou(account_id):
    suspended_accounts = get_suspended_account_ids()
    return account_id in suspended_accounts  # O(1) set lookup
```

---

## 1.0 vs 2.0 Account Check - Code Details

### Function: `check_account()` (Lines 241-258)

```python
def check_account(account_name):
    # Query DynamoDB table: operations-dev-cloud-versions
    # Key: account_name
    #
    # If FOUND → return True  → Account is 1.0 (legacy, exclude)
    # If NOT FOUND → return False → Account is 2.0 (include in report)
```

### Usage in Main Loop (Lines 416-428)

```python
is_one_dot_zero = check_account(account_name)
if not is_one_dot_zero and config_annotation:
    # Account is 2.0 AND has annotations → INCLUDE
    writer.writerow({...})
elif is_one_dot_zero:
    # Account is 1.0 → SKIP
    logger.info(f"Account {account_id} & {account_name} is 1.0 - skipping")
else:
    # Account is 2.0 but no matching annotations → SKIP
    logger.info(f"Account {account_id} & {account_name} - skipped (no matching annotations)")
```

---

## Log Output Examples

### Startup
```
Starting Config query
Current Time: 14:30:15
res types: ['vol-', 'i-', 'eni-']
```

### Suspended OU Cache
```
[SUSPENDED OU] Cached 2 suspended accounts
[SUSPENDED OU] Account IDs: 444455556666, 555566667777
```

### Account Processing
```
# Suspended account skipped
[SUSPENDED OU] Skipping account: 444455556666 (old-project)

# 1.0 account skipped
Account 333344445555 & legacy-finance is 1.0 - skipping

# 2.0 account with no matching annotations skipped
Account 777788889999 & dev-account - skipped (no matching annotations)

# 2.0 account with annotations included (no log, just writes to CSV)
```

### S3 Upload
```
# Layer 2: Safety net catches suspended account before CSV creation
[SUSPENDED OU] Skipping CSV creation for suspended account: 444455556666

# Successful uploads for non-suspended accounts
CSV saved to s3://my-bucket/config-reports/111122223333-prod-app-account_1.csv
CSV saved to s3://my-bucket/config-reports/222233334444-dev-test-account_1.csv
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| No accounts being skipped from Suspended OU | Wrong `SUSPENDED_OU_ID` | Verify the OU ID in AWS Organizations console |
| All accounts show as "1.0" | All accounts in DynamoDB table | Check `operations-dev-cloud-versions` table contents |
| AccessDeniedException | Missing IAM permissions | Add required Organizations/DynamoDB permissions |
| Nested OU accounts not excluded | Script only checks direct children | Move accounts directly under Suspended OU |

---

## Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": [
    "organizations:ListAccountsForParent",
    "organizations:DescribeAccount",
    "config:SelectAggregateResourceConfig",
    "config:GetAggregateComplianceDetailsByConfigRule",
    "dynamodb:Query",
    "s3:PutObject"
  ],
  "Resource": "*"
}
```

---

## Summary Table

| Check | Function | Data Source | TRUE means | FALSE means |
|-------|----------|-------------|------------|-------------|
| Suspended OU | `is_account_in_suspended_ou()` | AWS Organizations | Skip (suspended) | Continue processing |
| 1.0 Account | `check_account()` | DynamoDB table | Skip (legacy 1.0) | Include (2.0 account) |
