# How patch outcomes reach Splunk

AFT calls `patch-outcome-observability` in each patching region. The primary
Lambda deployment creates the account-wide writer role and common archive/enrichment
permissions inside the same module. Additional regions reuse that role with
`create_writer_role=false`. Every regional deployment adds its own log/queue
permissions and sources the unchanged shared Lambda/SQS modules. No separate
account module or repository is needed.

SSM sends command and invocation state changes to the regional default
EventBridge bus on a best-effort basis. Three rules select patch-document
success, invocation failure, and command-summary events. They are disabled by
default until the pilot is verified. The optional canary rule is enabled when
created and accepts manually sent `custom.patch-canary` events of detail type
`canary`; it has no timer or schedule.

The writer receives the original event. It resolves Scan versus Install from
command parameters and reads aggregate invocation status for ambiguous failures.
It can add command counts, agent health and EC2 tags where context is needed.
One ten-second budget covers all enrichment, including retries and cache work.
The remaining twenty seconds are reserved for the S3 write. If a lookup fails,
the writer retains available details and can emit `unknown`; it never invents
proof that a cancellation happened before execution.

The result is schema-2 JSON: `patched` for successful Install, `scanned` for
successful Scan, `failed` for confirmed execution failure, `not-attempted` for
explicit non-delivery/termination, or `unknown`. Command summaries and canaries
are separate record types. No outcome is a substitute for SSM Patch Compliance.

The writer performs a cross-account PutObject into the existing central outcomes
prefix. With SSE-KMS, S3 calls KMS on the writer's behalf. The central bucket/key
policies must authorize the actual organization and full role path. Only the
bucket's existing owners merge the rendered statements; Terraform here does not
manage any central bucket, key or notification configuration.

EventBridge target delivery failures go to the target DLQ. After Lambda accepts
an asynchronous event, exhausted retries or expiry can produce an invocation
record in its SQS on-failure destination. That message contains `requestPayload`
and failure metadata; it is not the raw event format of the EventBridge DLQ.
Replay extracts the original event and preserves its ID/time. See the
[central runbook](central-prerequisites/README.md) for commands and acknowledgement
rules. An event never delivered by SSM appears in neither queue.

Existing ingestion routes the sibling outcomes prefix into Splunk. The search
app parses schema 2, applies the action lookup, and correlates stdout by account,
region, command ID and instance ID. Event IDs prevent duplicate delivery from
inflating counts. Installation-state searches exclude scans, command summaries
and canaries; full history still shows scans and unresolved outcomes.

The [architecture](ARCHITECTURE.md), [payload contract](PAYLOAD-SPEC-patch-outcome-record.md)
and [build instructions](BUILD-INSTRUCTIONS-infrastructure.md) contain the
resource diagram, interfaces and verification steps.
