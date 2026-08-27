# Payload Specification — Patch Outcome Record

One flat JSON object per terminal invocation, newline-terminated, written to
`s3://<bucket>/patchingsolution-events/outcomes/dt=YYYY-MM-DD/<account>/…`

Indexed into the **same Splunk index** as the existing `AWS-RunPatchBaseline` stdout, under sourcetype **`aws:ssm:patch:outcome`**, joined to stdout on **`command_id`**.

---

## 1. The requirement this serves

> *"If I go to Splunk and pick up an instance, me/ops should see if it is patched, or failed, or terminated without patch — with their command ids."*

That requires a record for **every** terminal outcome, not only failures. A failure-only feed makes a cleanly patched instance return nothing, and "nothing" is indistinguishable from *never in scope* or *the pipeline broke*. Ops cannot trust a view with that ambiguity.

### `patch_outcome` — the one field to pivot on

| Ops question | `patch_outcome` | `status_details` |
|---|---|---|
| patched | `patched` | `Success` |
| failed | `failed` | `Failed`, `Execution Timed Out` |
| terminated without patch | `not-attempted` | `Terminated`, `Undeliverable`, `Delivery Timed Out`, `Invalid Platform`, `Access Denied` |

`patch_outcome` is what you filter and group on. `status_details` carries the precise reason underneath.

> **Caveat to state plainly:** `patched` means *the document ran and returned success* — not that every patch installed. `AWS-RunPatchBaseline` returns `Success` with a non-zero failed-patch count. This view answers *"did the patch run reach this box and complete"*. For true compliance use SSM Patch Compliance or the stdout summary.

---

## 2. The searches

### One instance, full history — the primary use case

```spl
index=aws_patching sourcetype="aws:ssm:patch:outcome" instance_id="i-0247e4245759c226c"
| table _time, patch_outcome, status_details, command_id, account
| sort - _time
```

```
_time                 patch_outcome   status_details   command_id
2026-08-26 17:01:39   not-attempted   Terminated       6da0f08c-9260-45fd-b855-8ebf7de5857e
2026-07-22 16:14:02   patched         Success          a71b3ef2-4c19-4d88-91aa-2f1c0e77b3d1
2026-06-24 15:58:41   failed          Failed           c04d9182-77be-4a02-8e3f-9d4a1b6c2e55
```

### Current state of the fleet — one row per instance

```spl
index=aws_patching sourcetype="aws:ssm:patch:outcome" earliest=-35d
| stats latest(patch_outcome) as outcome,
        latest(status_details) as reason,
        latest(command_id)    as command_id,
        latest(_time)         as last_run
    by account, instance_id
| where outcome!="patched"
| convert ctime(last_run)
```

Everything not currently patched, with the command ID to investigate. This is the compliance view.

### Drill from a failure into the actual error

```spl
index=aws_patching sourcetype="aws:ssm:patch:outcome" patch_outcome="failed"
| join type=left command_id
    [ search index=aws_patching sourcetype="aws:ssm:patch:stdout" ]
| table _time, instance_id, command_id, status_details, _raw
```

### One alert per command, not per instance

```spl
index=aws_patching sourcetype="aws:ssm:patch:outcome" patch_outcome!="patched"
| stats count(eval(patch_outcome="failed"))        as failed,
        count(eval(patch_outcome="not-attempted")) as not_attempted,
        values(max_errors) as max_errors, values(target_count) as targets
    by account, command_id
```

> One broken instance in a 38-node account produces 38 records sharing one `command_id`. Alerting per record means 38 pages for one full disk.

### Instances that vanished — the remaining blind spot

```spl
index=aws_patching sourcetype="aws:ssm:patch:outcome" earliest=-70d
| stats max(_time) as last_seen by account, instance_id
| where last_seen < relative_time(now(), "-35d")
```

An instance that stops producing *any* outcome record has lost its patch tag, been terminated, or dropped out of SSM. Absence is still ambiguous — closing it fully needs an inventory join, which is out of scope here.

---

## 3. The records

### `patched` — highest volume, cheapest. Zero API calls.

```json
{"schema_version":1,"record_type":"invocation","account":"111122223333","region":"us-east-1","instance_id":"i-0247e4245759c226c","command_id":"6da0f08c-9260-45fd-b855-8ebf7de5857e","document":"AWS-RunPatchBaseline","event_time":"2026-08-26T17:01:39Z","patch_outcome":"patched","status":"Success","status_details":"Success"}
```

**324 bytes.** Success needs no enrichment — it worked, there is nothing to explain, and the event alone is conclusive.

### `failed` — thin, because stdout has the rest

```json
{"schema_version":1,"record_type":"invocation","account":"111122223333","region":"us-east-1","instance_id":"i-0d08dfc84192173d0","command_id":"6da0f08c-…","document":"AWS-RunPatchBaseline","event_time":"2026-08-26T17:01:39Z","patch_outcome":"failed","status":"Failed","status_details":"Failed"}
```

**321 bytes**, one API call. A full stdout object already exists in Splunk; join on `command_id` rather than duplicating any of it.

### `not-attempted` — self-sufficient, because nothing else records it

```json
{"schema_version":1,"record_type":"invocation","account":"111122223333","region":"us-east-1","instance_id":"i-0247e4245759c226c","command_id":"6da0f08c-…","document":"AWS-RunPatchBaseline","event_time":"2026-08-26T17:01:39Z","patch_outcome":"not-attempted","status":"Failed","status_details":"Terminated","target_count":38,"error_count":1,"completed_count":38,"max_errors":"2%","max_concurrency":"10%","command_comment":"300185ff-5509-4b3f-93d5-768cab904b63:8a47da2a","agent_ping_status":"Online"}
```

**524 bytes**, three API calls (one usually a cache hit). **No stdout object was ever written for this instance** — it was never touched — so this record is the only evidence it was in scope and got skipped. It has to stand alone.

---

## 4. Sizing principle

> Record size is *inverse* to how much stdout already tells you.

| `patch_outcome` | stdout exists? | Extra fields | Size | API calls |
|---|---|---|---|---|
| `patched` | yes | none — nothing to explain | **324 B** | **0** |
| `failed` | yes — the full error | none — join on `command_id` | **321 B** | 1 |
| `not-attempted` | **no** | command counts, rate controls, agent status | **524 B** | 3 |

All measured against the handler, not estimated. Add ~139 B and one API call if `INCLUDE_INSTANCE_TAGS=true`.

### Field inventory

**Always present (11 fields)** — `schema_version`, `record_type`, `account`, `region`, `instance_id`, `command_id`, `document`, `event_time`, `patch_outcome`, `status`, `status_details`.

**`not-attempted` only (7 fields)** — because these instances have no other record anywhere:

| Field | Source | Why |
|---|---|---|
| `agent_ping_status` | `DescribeInstanceInformation` | usually *is* the answer. `ConnectionLost` turns a mystery into a known cause. |
| `target_count`, `error_count`, `completed_count` | `ListCommands` | *"36 of 38 never attempted"* — the whole picture inside one record |
| `max_errors`, `max_concurrency` | `ListCommands` | **makes the record self-documenting.** A reader needs no knowledge of the 2% policy to understand why this instance was skipped. |
| `command_comment` | `ListCommands` | `300185ff-…:<per-execution>` — an association/window ID. Wave-level correlation with no other source. |

**Optional** — `instance_name`, `tag_application`, `tag_owner`, `tag_patch_wave` from `DescribeInstances`. **Turn OFF if Splunk has an instance-ID → owner lookup**: saves ~139 B and one API call per record, and avoids stale tags frozen into an immutable object.

---

## 5. Volume

| | |
|---|---|
| Success records, 450 acct × ~30 inst, monthly cycle | **~4.2 MB/month** |
| Same, weekly cycle | ~17 MB/month |
| A halted 38-node command | **19.2 KB** |

Success is the highest-volume class and the smallest record — that combination is deliberate. Against the stdout volume already flowing into the same index, this is noise.

---

## 6. What is deliberately not sent

| Excluded | Bytes saved | Where it lives instead |
|---|---|---|
| `stderr_excerpt` | 8,000 | It *is* stderr — already indexed. Join on `command_id`. |
| `stdout_tail` | 2,000 | Already indexed. |
| patch counts, baseline, reboot option | ~400 | `AWS-RunPatchBaseline` prints the summary in stdout; SSM Patch Compliance is the system of record. Also saves an API call. |
| Verbatim `event` block | ~500 | Every field of interest is already extracted |
| `stdout_s3_url` / `stderr_s3_url` / path | ~250 | The join is `command_id` field-to-field |
| `execution_start/end`, `response_code`, `plugin_name` | ~150 | In stdout; null for `Terminated` anyway |
| `instance_type`, `az`, `image_id`, `agent_version`, `platform_*` | ~200 | Derivable from `instance_id` at search time |
| `recommended_action` | ~120 | **A Splunk lookup on `patch_outcome` + `status_details`** — one editable table beats the same sentence on every record, and rewording it no longer means redeploying 450 Lambdas |
| Nested structs | ~80 | Flattened — no `FIELDALIAS` stanzas needed |

---

## 7. EventBridge rules — three, not two

| Rule | detail-type | `detail.status` | → Lambda |
|---|---|---|---|
| `invocation-success` | `EC2 Command Invocation Status-change Notification` | `["Success"]` | **yes** |
| `invocation-failure` | `EC2 Command Invocation Status-change Notification` | `["Failed","TimedOut","Cancelled","Undeliverable","Terminated"]` | yes |
| `command-failure` | `EC2 Command Status-change Notification` | `["Failed","TimedOut","Cancelled","Undeliverable","Incomplete","AccessDenied","DeliveryTimedOut"]` | yes |

> **This reverses earlier guidance.** A previous revision said the success rule must not reach the Lambda, to avoid S3 object sprawl. That held while the archive was failure-only. It no longer does: the success record *is* the deliverable — without it, an instance that patched cleanly returns nothing in Splunk and ops cannot tell that apart from a broken pipeline.

All three go on the **default** bus. SSM service events are delivered nowhere else.

---

## 8. Splunk parsing

```ini
[aws:ssm:patch:outcome]
INDEXED_EXTRACTIONS     = json
KV_MODE                 = none
SHOULD_LINEMERGE        = false
LINE_BREAKER            = ([\r\n]+)
TRUNCATE                = 4000

# Event time, never ingest time.
TIMESTAMP_FIELDS        = event_time
TIME_FORMAT             = %Y-%m-%dT%H:%M:%SZ
MAX_TIMESTAMP_LOOKAHEAD = 32
```

Flat JSON means **no `FIELDALIAS` stanzas** — every field lands with its final name.

Ship a lookup table `patch_outcome_action.csv` so the wording lives in one editable place:

```csv
patch_outcome,status_details,action
patched,Success,"Patch run completed. Check SSM Patch Compliance for installed/missing counts."
failed,Failed,"Patch ran and failed. Read the stdout for this command_id."
failed,Execution Timed Out,"Patch started but did not finish. Check instance load and the execution timeout."
not-attempted,Terminated,"Never attempted -- the command halted at its error threshold. Re-run. See max_errors."
not-attempted,Undeliverable,"Unreachable by SSM. Check agent and connectivity, then re-run."
not-attempted,Delivery Timed Out,"Command never delivered. Check agent and connectivity, then re-run."
not-attempted,Invalid Platform,"Document does not match this OS. Targeting defect."
not-attempted,Access Denied,"Instance profile or permissions defect. Fix before re-running."
```

---

## 9. Open decisions

1. **Is `command_id` already an extracted field on the stdout sourcetype**, or does it need a `rex` on the S3 object path? Every drill-down search depends on it. This is the single most important thing to confirm with the Splunk team.
2. **Does Splunk have an instance-ID → owner lookup?** If yes, set `INCLUDE_INSTANCE_TAGS=false`.
3. **Patch cycle frequency** — monthly or weekly? Decides whether success volume is ~4 MB or ~17 MB per month.
4. **Should `failed` records carry `target_count` / `error_count` too?** ~55 B. It would let the command-level alert work off any single record rather than needing the whole group.
5. **Retention** for the outcomes prefix in S3 and in the Splunk index — the fleet-state search only needs ~35 days, but audit may want longer.
