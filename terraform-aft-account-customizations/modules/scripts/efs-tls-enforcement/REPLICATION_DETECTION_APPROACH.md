# EFS Replication Destination Detection — Approach Decision

## What We Need to Do

When AWS Config evaluates an EFS file system for TLS enforcement, replication
**destination** file systems must be skipped. They are read-only and cannot have
a resource policy attached, so requiring one would always produce a false
`NON_COMPLIANT` result.

---

## Two Approaches Considered

### Approach A — Targeted call (current implementation)

```python
response = get_efs_client().describe_replication_configurations(
    FileSystemId=file_system_id
)
for replication in response.get('Replications', []):
    for destination in replication.get('Destinations', []):
        if destination.get('FileSystemId') == file_system_id:
            return True
return False
```

### Approach B — Paginator over all replications (considered, not used)

```python
paginator = efs.get_paginator('describe_replication_configurations')
for page in paginator.paginate():          # no FileSystemId filter
    for config in page.get('Replications', []):
        for dest in config.get('Destinations', []):
            if dest.get('FileSystemId') == file_system_id:
                return 'EXCLUDE'
```

---

## Why Approach A (Targeted Call)

| Reason | Detail |
|--------|--------|
| **Scoped to one file system** | Passing `FileSystemId=x` tells the API to return only the replication config for that specific file system. No unnecessary data is fetched. |
| **Single API call** | One EFS file system can be a destination in at most one replication relationship. The response will have at most one `Replications` entry — pagination adds no value. |
| **Faster Lambda execution** | Each AWS Config evaluation triggers this Lambda per EFS file system. A single targeted call keeps execution time minimal. |
| **Lower cost** | Fewer API calls = fewer charges, especially in accounts with many EFS file systems being evaluated simultaneously. |
| **Narrower IAM permissions** | The Lambda's IAM policy can be scoped to `elasticfilesystem:DescribeReplicationConfigurations` on specific resources, reducing blast radius. |

---

## Why Not Approach B (Paginator Over All)

| Reason | Detail |
|--------|--------|
| **Scans the entire account** | `paginator.paginate()` with no `FileSystemId` filter fetches **every** replication configuration in the account on every single evaluation. |
| **O(n) API calls per evaluation** | With 50 EFS file systems and 10 replications, that is 50 full account-wide scans — 500 unnecessary API reads per Config cycle. |
| **Pagination is pointless here** | A destination EFS can only belong to one replication relationship. There is never more than one page of results for a single file system. |
| **Lambda timeout risk** | In large accounts with hundreds of replication configs, paginating all of them on every evaluation risks hitting the Lambda timeout. |
| **Broader IAM permissions required** | Listing all replications without a resource filter requires unrestricted `DescribeReplicationConfigurations`, which is a wider permission than necessary. |
| **Wrong return type** | Returning the string `'EXCLUDE'` instead of a boolean `True`/`False` is inconsistent with the function's contract and relies on truthiness by accident. |

---

## Why Not the Old Tag-Based Approach

Before either of the above, the code checked for the `aws:backup:source-resource-arn`
tag to identify read-only EFS copies.

**Problem:** This tag is present on **both** source and destination EFS file systems
involved in backup/replication workflows. It cannot reliably distinguish a read-only
destination from a writable source, causing legitimate source file systems to be
incorrectly skipped from TLS evaluation.

The replication API (`describe_replication_configurations`) is the authoritative source
of truth — if the file system ID appears in `Destinations`, it is definitively read-only.

---

## Decision Summary

```
Approach A  ✅  One targeted API call, scoped to the file system being evaluated.
Approach B  ❌  Full account scan on every evaluation — correct logic, wrong scope.
Tag check   ❌  Unreliable — tag appears on both source and destination file systems.
```
