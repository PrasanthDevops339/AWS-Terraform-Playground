# cloud-ops-governance-platform — Script Changes

> Last Updated: February 2026

---

## Status Overview

| # | Script | Change | Type | Status |
|---|--------|--------|------|--------|
| F1 | `complianceRulesExecution.py` | Loop structure — collect ALL matching resource rows per rule | Bug Fix | ✅ Applied |
| F2 | `servicenow_eventmanager.py` | SELECT query scoped to `ruleId` + `LIMIT 1` | Bug Fix | ✅ Applied |
| F3 | `servicenow_eventmanager.py` | UPDATE query scoped to `ruleId` | Bug Fix | ✅ Applied |
| F4 | `servicenow_eventmanager.py` | `download_csv_to_tmp` local path construction | Bug Fix | ✅ Applied |

---

## F1 — `complianceRulesExecution.py`: Loop Structure Fix

**File:** `scripts/complianceRulesExecutionLambda/complianceRulesExecution.py`

### Problem

The outer loop iterated over **each ingest row** (per resource), with `data = []` reset on every row and a `return` statement inside the nested loops. This meant:

- Only the **first matching resource row** was ever added to `data`
- The processed CSV written to S3 had exactly **1 resource row**, regardless of how many non-compliant resources existed
- A `DELETE FROM ingest` ran after the first match, silently dropping all remaining resources
- Because each run produced a different 1-resource hash, the `actions` table accumulated **multiple orphan rows** per `(accountId, ruleId)` over time
- `servicenow_eventmanager.py` then found multiple `actions` rows and created **one ticket per orphan row**

```python
# BEFORE — resets data per resource row, returns after first match
for row in rows:          # outer: each resource
    data = []
    for rule in rules:    # inner: each enabled DynamoDB rule
        if int(rule_id) == row[1]:
            data.append(row)   # only ever 1 row in data
            if len(data):
                # write 1-resource CSV
                # insert/update actions
                # delete ALL ingest
                return         # exits after first resource
```

### Fix

Flipped the loop structure — outer loop over **rules**, inner loop collects **all ingest rows** matching that rule. The `return` and `DELETE FROM ingest` were moved outside both loops so they run once after all rules are processed.

```python
# AFTER — collects ALL matching resource rows per rule before processing
snow_action_type = ''
matched_rule = None

for rule in rules:        # outer: each enabled DynamoDB rule
    rule_id = list(rule['id'].values())[0]

    # collect ALL ingest rows that match this rule (not just the first)
    data = []
    for row in rows:
        if int(rule_id) == row[1]:
            data.append(list(row))

    if not data:
        print(f"No match on {rule['id']} - {rule['description']}")
        continue

    matched_rule = rule_id
    # sort ALL matching rows, compute hash, write complete CSV, insert/update actions
    sorted_data = sorted(data, key=lambda x: (x[2], x[5], x[7], x[8], x[13]))
    hashed = hashlib.sha256(json.dumps(sorted_data).encode('utf-8')).hexdigest()
    # ... write CSV and insert actions ...

# delete ingest ONCE after all rules processed
cursor.execute("DELETE FROM ingest WHERE accountId=%s AND source=%s", (account_id, source))
conn.commit()

return {
    "statusCode": 200,
    "rule_id": matched_rule if matched_rule else '',
    "snow_action_type": snow_action_type
}
```

### Impact

- Processed CSV now contains **all N non-compliant resources** for the rule, not just 1
- Hash is computed over all resources → stable across runs → no new orphan rows in `actions`
- `DELETE FROM ingest` runs once after all rules are checked, not per-resource

---

## F2 — `servicenow_eventmanager.py`: SELECT Query Scoped to `ruleId`

**File:** `scripts/serviceNowEventManagerLambda/servicenow_eventmanager.py` — line ~472

### Problem

The `SELECT` query had no `ruleId` filter, returning **all pending `actions` rows for the account** regardless of which rule the current step function execution was processing. With multiple enabled rules, multiple rows existed in `actions` for the same account, causing one ticket per row.

Additionally, because the `actions` PRIMARY KEY is `(accountId, ruleId, hash)`, orphan rows with different hashes accumulated for the same rule across runs, each with `executed=0`.

```python
# BEFORE — no ruleId filter, no row limit
query = "SELECT * FROM actions WHERE source=%s AND accountId=%s AND executed=0"
params = (source, account_id)
```

### Fix

Added `AND ruleId=%s` to scope to the specific rule being processed, and `ORDER BY timestamp DESC LIMIT 1` to always select the most recent row (handles any existing orphan rows).

```python
# AFTER — scoped to rule, latest row only
query = "SELECT * FROM actions WHERE source=%s AND accountId=%s AND ruleId=%s AND executed=0 ORDER BY timestamp DESC LIMIT 1"
params = (source, account_id, rule_id)
```

### Impact

- `account_files` list always has **at most 1 entry** per step function execution
- Exactly **1 ticket** is created per execution
- Orphan rows from previous runs are handled (picked up only if most recent, then cleaned up by F3)

---

## F3 — `servicenow_eventmanager.py`: UPDATE Query Scoped to `ruleId`

**File:** `scripts/serviceNowEventManagerLambda/servicenow_eventmanager.py` — line ~561

### Problem

The `UPDATE` that marks rows as `executed=1` had no `ruleId` filter. It updated **all rules for the account**, which could mark unrelated rules' rows as done prematurely in concurrent step function executions.

```python
# BEFORE — updates all rules for the account
sql = "UPDATE actions SET executed=%s, state=%s WHERE source=%s AND accountId=%s"
val = (1, json.dumps(state_data), source, account_id)
```

### Fix

Added `AND ruleId=%s` to scope the update to the specific rule. This also has the side effect of cleaning up **all orphan rows** for that rule in one shot (since the WHERE clause matches all rows for that `ruleId`, regardless of hash).

```python
# AFTER — scoped to specific rule
sql = "UPDATE actions SET executed=%s, state=%s WHERE source=%s AND accountId=%s AND ruleId=%s"
val = (1, json.dumps(state_data), source, account_id, rule_id)
```

### Impact

- Only the current rule's rows are marked `executed=1`
- All orphan rows for that rule (different hashes from old runs) are cleaned up in the same UPDATE
- Concurrent executions for other rules are not affected

---

## F4 — `servicenow_eventmanager.py`: `download_csv_to_tmp` Path Construction

**File:** `scripts/serviceNowEventManagerLambda/servicenow_eventmanager.py` — line ~232

### Problem

The local `/tmp` path was built by splitting the S3 key basename on `-` and taking index `[1]`. The actual S3 key stored in `actions.artifact` is:

```
processed/aws-config/{accountId}/{ruleId}_{date}.csv
```

The basename is `{ruleId}_{date}.csv` (e.g., `5_02272026.csv`) — **no hyphens**. Splitting on `-` returned a single-element list, causing an `IndexError`. The `except` block caught it silently and returned `None`, which caused the `if not local_path: continue` guard in `lambda_handler` to **skip ticket creation entirely**.

```python
# BEFORE — IndexError when basename has no hyphen
local_path = f"/tmp/{account_id + '_' + os.path.basename(s3_key).split('-')[1]}"
```

### Fix

Use the basename directly to build a unique, valid temp path.

```python
# AFTER — always works regardless of filename format
local_path = f"/tmp/{account_id}_{os.path.basename(s3_key)}"
```

**Example:** for `s3_key = "processed/aws-config/596XXXXXXXXX/5_02272026.csv"` and `account_id = "wld-dev"`:
- Before: `IndexError` → `None` → ticket skipped
- After: `/tmp/wld-dev_5_02272026.csv` → file downloaded → ticket created with CSV attached

### Impact

- CSV file is now successfully downloaded to `/tmp`
- `create_snow_ticket()` receives a valid `csv_path` and attaches the CSV to the ServiceNow incident
- The ticket attachment (all N non-compliant resources) now works end-to-end

---

## End-to-End Flow After All Fixes

For an account with 10 non-compliant EFS resources (rule 5):

```
1. config_aggregator.py uploads:
   ingest/aws-config/{accountId}_{accountName}_5.csv  ← 10 resources

2. EventBridge fires ONCE → 1 Step Function execution starts

3. compliance_ingest.py:
   Inserts 10 rows into ingest table (one per resource, id=5)

4. complianceRulesExecution.py (F1 fixed):
   SELECT * FROM ingest WHERE source AND accountId → 10 rows
   Outer loop: rule 5 matches → data = [all 10 rows]
   hash = sha256(all 10 sorted rows)  ← stable
   Writes processed/.../5_MMDDYYYY.csv with 10 resources
   INSERT INTO actions (accountId, ruleId=5, hash, artifact=above key)
   DELETE all 10 rows from ingest
   Returns { rule_id: 5, snow_action_type: 'Create' }

5. servicenow_eventmanager.py (F2/F3/F4 fixed):
   SELECT ... WHERE ruleId=5 AND executed=0 ORDER BY timestamp DESC LIMIT 1
   → 1 row → s3_key = processed/.../5_MMDDYYYY.csv
   download_csv_to_tmp() → /tmp/wld-dev_5_MMDDYYYY.csv  (10 resources)
   create_snow_ticket() → 1 INC created, 10-resource CSV attached
   UPDATE actions SET executed=1 WHERE ruleId=5  ← cleans up orphan rows

Result: 1 ticket, 10-resource CSV attached ✓
```

---

## Root Cause Summary

| Finding | Root Cause | Fix |
|---------|-----------|-----|
| Multiple tickets for same rule | `actions` table accumulated orphan rows (different hashes) because complianceRulesExecution processed 1 resource per run | F1: collect all resources → stable hash |
| Tickets created for wrong rules | SELECT had no `ruleId` filter | F2: add `AND ruleId=%s LIMIT 1` |
| Other rules' actions marked done | UPDATE had no `ruleId` filter | F3: add `AND ruleId=%s` |
| No CSV attached to ticket | `.split('-')[1]` IndexError on filename without hyphens | F4: use basename directly |
