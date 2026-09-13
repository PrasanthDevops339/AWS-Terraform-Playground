# Payload contract — schema version 2

One flat, newline-terminated JSON object is written for each delivered SSM
terminal-status event or manual canary. It lands at:

```text
s3://<bucket>/<prefix>/dt=YYYY-MM-DD/<account>/<region>/<record_type>_<event_id>.json
```

The default prefix is `patchingsolution-events/outcomes`, a sibling of the
existing stdout prefix. The date comes from the event's UTC timestamp. A replay
of the same event uses the same key. A versioned bucket can retain multiple
versions, and downstream notifications can duplicate indexing; consumers must
still deduplicate `account`, `region`, `event_id`.

## Fields

| Field | Type / meaning |
|---|---|
| `schema_version` | Integer `2`. |
| `record_type` | `invocation`, `command`, or `canary`. |
| `event_id` | Original EventBridge ID; preserved during replay. |
| `account`, `region` | Originating account and region. |
| `event_time` | Original event time normalized to UTC with milliseconds, e.g. `2026-09-08T12:00:00.000Z`. |
| `instance_id` | Present only on invocation records; EC2 `i-` or managed-node `mi-` ID. |
| `command_id`, `document` | SSM command/document identity; null on canaries. |
| `operation` | `Scan`, `Install`, or `unknown`. |
| `status` | Raw EventBridge status; null on canaries. |
| `status_details` | Canonical terminal invocation detail when established, otherwise null. |
| `patch_outcome` | `patched`, `scanned`, `failed`, `not-attempted`, or `unknown`. |

Only invocation records receive instance outcomes. Command summaries and
canaries have `patch_outcome=unknown`; dashboards must filter record type.

| Evidence | Invocation outcome |
|---|---|
| Success event + Install operation | `patched` |
| Success event + Scan operation | `scanned` |
| Success event without a resolved operation | `unknown` |
| Explicit Terminated, Undeliverable, Delivery Timed Out, Invalid Platform, Access Denied | `not-attempted` |
| Aggregate invocation details Failed / Execution Timed Out, or explicit execution-timeout event | `failed` |
| Cancelled, ambiguous coarse Failed/TimedOut without details, unavailable enrichment | `unknown` |

Status spelling is normalized internally, including spaced/compact timeout and
platform/access-denied variants. An explicit non-delivery event is sufficient
even if enrichment is disabled. Cancellation can occur after execution starts;
unknown avoids asserting that an instance was untouched.

`patched` is command execution success, **not** proof of patch compliance or
reboot completion. `scanned` performs no installation. AWS documents these
operations in [AWS-RunPatchBaseline](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-aws-runpatchbaseline.html).

## Enrichment and timing

Failures use `ListCommandInvocations(CommandId, InstanceId, Details=false)` for
aggregate managed-node status; plugin-level `GetCommandInvocation` is not used.
Missing or nonterminal results receive up to three attempts, with short backoff,
within the shared budget. Success skips this status lookup but usually needs
`ListCommands` because invocation events omit command parameters. Operation in
the event takes precedence; cached command parameters fill missing information.

The command cache is bounded to 128 entries with a fifteen-second TTL, per warm
Lambda environment. Empty/failed reads are not cached. Command counts are a
recent API snapshot, not a guarantee that every target has finished or been
observed. Separate Lambda environments do not share cached command data.

Unknown/non-delivery invocations can include `target_count`, `error_count`,
`completed_count`, `max_errors`, `max_concurrency`, `command_comment` and
`agent_ping_status`. Command records can include the command fields. Optional
`instance_name`, `tag_application`, `tag_owner`, `tag_patch_wave` are added only
to invocation records needing context; hybrid managed nodes skip EC2 tags.
Confirmed patched/scanned/failed records stay small.

All enrichment shares a ten-second deadline enforced by a POSIX timer on the
managed Lambda runtime's main thread. SDK calls use one attempt with one-second
connect and two-second read timeouts; short eventual-consistency retries are
owned by the handler. The budget shrinks when less than thirty seconds remain,
reserving twenty seconds for S3. Exhaustion or enrichment exceptions retain
available fields and continue to delivery. The timer is cleared before S3.
S3 uses bounded standard SDK retries; write failures propagate to Lambda's async
retry/failure-destination mechanism. Unexpected malformed event envelopes fail
rather than creating misleading patch records.

## Example

```json
{"schema_version":2,"record_type":"invocation","event_id":"22222222-2222-2222-2222-222222222222","account":"222233334444","region":"us-east-1","command_id":"11111111-1111-1111-1111-111111111111","document":"AWS-RunPatchBaseline","event_time":"2026-09-08T12:00:00.000Z","operation":"Scan","status":"Success","status_details":"Success","instance_id":"i-0123456789abcdef0","patch_outcome":"scanned"}
```

No stdout, stderr excerpts, patch counts, original nested event or recommended
action text is copied into the record. Existing stdout is correlated on
**account + region + command_id + instance_id**. Recommendation text comes from
the Splunk lookup. See [the supplied searches](splunk/README.md).

## Coverage and compatibility

SSM delivers service events on a best-effort basis. There is no reconciliation
poller or inventory join. Command records do not synthesize missing per-instance
records, and absence is not proof of compliance, exclusion, or non-execution.
The canary verifies downstream delivery but cannot establish SSM event coverage.

Schema 2 adds operation/event identity and scanned/canary distinctions and fixes
classification. New searches explicitly filter schema 2. If schema 1 data exists,
retain it as historical data and update consumers before rollout; do not merge
it into the new installation-state view without a separate migration policy.
