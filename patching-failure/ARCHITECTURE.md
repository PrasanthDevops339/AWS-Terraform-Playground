# Patch outcome architecture

A single-account, single-region Terraform root in `patching-failure/`. Patching
is owned by the centralized Quick Setup patch policy; this root only captures
outcomes. Examples use dummy account `222233334444` and a central bucket in
dummy account `111122223333`.

```mermaid
flowchart TB
    QS["Central Quick Setup patch policy<br/>State Manager associations<br/>AWS-RunPatchBaseline Scan / Install"]
    subgraph ACCOUNT["POC account — one region"]
        ROLE["Lambda execution role<br/>patch-outcome-s3-writer (optional path)<br/>archive + enrichment policy<br/>logs runtime policy"]
        SSM["SSM Run Command status events"]
        subgraph BUS["EventBridge default bus"]
            R1["invocation_success<br/>Success"]
            R2["invocation_failure<br/>Terminal failure / non-delivery statuses"]
            R3["command_failure<br/>Command summaries"]
            RC["Optional canary rule<br/>custom.patch-canary + detail-type canary"]
        end
        CLI["Operator: manually sends canary"]
        FN["Shared terraform-aws-lambda module<br/>alias-prefix-region-writer<br/>handler.handler / Python 3.13 / 30 s<br/>2 async retries, 6 h max age"]
        PKG[("S3 package bucket<br/>prefix-pkg-account-region<br/>SSE-KMS with local package CMK")]
        READS["Bounded enrichment — at most 10 s<br/>SSM ListCommandInvocations / ListCommands<br/>agent status / optional EC2 tags"]
        LOGS[("Existing app_log/ log group (not managed)<br/>Lambda-created streams + metrics<br/>failure visibility")]
        SSM --> R1 & R2 & R3
        R1 & R2 & R3 --> FN
        CLI --> RC --> FN
        FN --> LOGS
        FN -. optional API reads .-> READS
        PKG --> FN
        ROLE -. execution identity .-> FN
    end
    subgraph CENTRAL["Existing central account — owned by other teams"]
        POLICY["Existing bucket + KMS policies<br/>Merge rendered statements manually"]
        BUCKET[("Existing archive bucket<br/>patchingsolution-events/outcomes/")]
        KEY{{"Existing central KMS CMK<br/>Archive is SSE-KMS"}}
        INGEST["Existing s3tofirehose ingestion"]
        SPLUNK[("Splunk: aws:ssm:patch:outcome")]
        POLICY -. authorizes .-> BUCKET
        POLICY -. authorizes .-> KEY
        BUCKET -. GenerateDataKey on writer's behalf .-> KEY
        BUCKET --> INGEST --> SPLUNK
    end
    QS --> SSM
    FN ==>|"Cross-account PutObject<br/>SSE-KMS with central CMK"| BUCKET
    STDOUT[("Existing aws:ssm:patch:stdout")] -. "correlate account + region + command_id + instance_id" .-> SPLUNK
```

## Identity and dependencies

`iam.tf` creates one role with a fixed name and path, so that the central policies
can authorize it with `arn:<partition>:iam::*:role<path><name>`. The role carries
two inline policies: `archive`, which covers central S3/KMS writes and optional
SSM/EC2 reads, and `runtime`, which lets Lambda create log streams in the existing
`app_log/` group.

The shared Lambda module is used unchanged. It prefixes the function name with
the account alias, which must exist and keep the name within 64 characters. It
deploys only from S3, so this root creates an SSE-KMS package bucket. The log
group is looked up with a data source, so the plan fails if `app_log/` is
missing. Bucket protection and both IAM policies are created before the function, and the
EventBridge targets follow the function and its async configuration. IAM
propagation can still require AWS retries during the first apply.

## Outcomes and delivery

| Record | Meaning |
|---|---|
| `invocation`, `patched` | An **Install** invocation returned Success; verify actual compliance and reboot state separately. |
| `invocation`, `scanned` | A **Scan** invocation returned Success; no installation is implied. |
| `invocation`, `failed` | Aggregate invocation details establish failure or execution timeout. |
| `invocation`, `not-attempted` | Explicit termination by error threshold or a non-delivery/targeting status. |
| `invocation`, `unknown` | Operation or execution stage is unresolved. Cancellation alone does not prove non-execution. |
| `command` | Command-level context; never counted as an instance outcome. |
| `canary` | Synthetic pipeline check; never counted as patch activity. |

SSM service events use [best-effort delivery](https://docs.aws.amazon.com/eventbridge/latest/ref/events-ref-ssm.html).
Nothing reconciles missed events. Duplicate delivery is possible; repeated
writes use the same event-based key, and Splunk deduplicates on event ID. A
canary proves downstream delivery once its event is found in Splunk; it does not
prove that real SSM event patterns match.

## Planned enhancement: dead-letter queues

The code is kept commented out in `main.tf`, `iam.tf` and `outputs.tf`, marked
`ENHANCEMENT (DLQ)`. When restored, it adds:

- an EventBridge target DLQ holding the original event when a target cannot invoke the Lambda;
- a Lambda async on-failure destination holding an invocation record with `requestPayload`;
- a queue policy scoped to these rules and account, plus a `sqs:SendMessage` grant.

Both queues come from the shared `terraform-aws-sqs` module with 14-day
retention. Restoring them adds 3 resources.

## Deployment boundary

`rules_enabled` defaults to `false`. The canary rule is enabled when created, but
there is no schedule; an operator sends the event by hand. No custom metrics,
alarms, SNS topics, queues, central resources or bucket notifications are created.
Packages, retained logs, requests and any KMS usage can incur charges even while
SSM rules are disabled.

See [BUILD-INSTRUCTIONS-infrastructure.md](BUILD-INSTRUCTIONS-infrastructure.md)
for deployment and tests, [PAYLOAD-SPEC-patch-outcome-record.md](PAYLOAD-SPEC-patch-outcome-record.md)
for the record contract, [central-prerequisites/README.md](central-prerequisites/README.md)
for cross-account access and replay, and [splunk/README.md](splunk/README.md)
for parsing, correlation and acceptance.
