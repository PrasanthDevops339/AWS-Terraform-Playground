# How patch outcomes reach Splunk

The organization's centralized **Quick Setup patch policy** schedules scans and
installs. Its State Manager associations run `AWS-RunPatchBaseline` on managed
nodes. This POC deploys into one account and one region to observe those runs; it
never starts, changes or schedules patching.

SSM sends command and invocation state changes to the regional default
EventBridge bus on a best-effort basis. Three rules select patch-document
success, invocation failure, and command-summary events by matching the
`AWS-RunPatchBaseline` document-name prefix. They are disabled by default until
the canary is verified. The optional canary rule is enabled when created and
accepts manually sent `custom.patch-canary` events of detail type `canary`; it
has no timer or schedule.

The writer Lambda (shared `terraform-aws-lambda` module) receives the original
event. It resolves Scan versus Install from command parameters and reads
aggregate invocation status for ambiguous failures. It can add command counts,
agent health and EC2 tags where context is needed. One ten-second budget covers
all enrichment, including retries and cache work. The remaining twenty seconds
are reserved for the S3 write. If a lookup fails, the writer keeps the details it
has and can emit `unknown`; it never invents proof that a cancellation happened
before execution.

Quick Setup scans daily, so expect a steady volume of `scanned` records alongside
the less frequent install outcomes. Invocation events often omit command
parameters; the writer then calls `ssm:ListCommands`. During the POC, confirm
that association-launched commands resolve there. If they do not, successful
installs are recorded as `unknown` instead of `patched`.

The result is schema-2 JSON: `patched` for successful Install, `scanned` for
successful Scan, `failed` for confirmed execution failure, `not-attempted` for
explicit non-delivery/termination, or `unknown`. Command summaries and canaries
are separate record types. No outcome is a substitute for SSM Patch Compliance.

The writer performs a cross-account PutObject into the existing central outcomes
prefix. With SSE-KMS, S3 calls KMS on the writer's behalf. The central bucket/key
policies must authorize the actual organization and full role path. Only the
bucket's existing owners merge the rendered statements; Terraform here does not
manage any central bucket, key or notification configuration.

## Failure visibility (basic path)

The SQS dead-letter queues are a disabled enhancement, so no failed event is
stored for replay. Failures show up here instead:

| Failure | Where it is visible |
|---|---|
| EventBridge cannot invoke the Lambda (permission, throttling) | EventBridge rule metric `FailedInvocations` (namespace `AWS/Events`). |
| Handler error, such as S3 or KMS AccessDenied | Lambda log group `/aws/lambda/<alias>-<prefix>-<region>-writer` and the Lambda `Errors` metric. Lambda retries twice. |
| Retries exhausted or event older than six hours | Lambda `AsyncEventsDropped` metric; the event body is in the earlier error log lines. |
| SSM never emitted the event | Nowhere; delivery is best effort. |

To recover an event, take the original event JSON from the logs (at `LOG_LEVEL=DEBUG`,
or rebuild it from the SSM command/instance IDs) and replay it with a synchronous
`aws lambda invoke`, as described in the [central runbook](central-prerequisites/README.md).
The DLQ enhancement in `main.tf` restores durable capture when it is needed.

Existing ingestion routes the sibling outcomes prefix into Splunk. The search
app parses schema 2, applies the action lookup, and correlates stdout by account,
region, command ID and instance ID. Event IDs prevent duplicate delivery from
inflating counts. Installation-state searches exclude scans, command summaries
and canaries; full history still shows scans and unresolved outcomes.

The [architecture](ARCHITECTURE.md), [payload contract](PAYLOAD-SPEC-patch-outcome-record.md)
and [build instructions](BUILD-INSTRUCTIONS-infrastructure.md) contain the
resource diagram, interfaces and verification steps.
