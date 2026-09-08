# Patch outcome architecture

Use `patch-outcome-observability` for each patching region. The first deployment
creates the Lambda execution role within that module; additional regions reuse it. The example uses two dummy members (`222233334444`,
`333344445555`), two regions, and an existing central bucket in dummy account
`111122223333`. Repeat the same account customization independently across the
fleet. A single member-account Terraform state owns its identity and regions.

```mermaid
flowchart TB
    subgraph MEMBER["Member account — repeat through AFT"]
        subgraph REGION["patch-outcome-observability — primary region, create_writer_role=true"]
            ROLE["Included Lambda execution role<br/>One account-wide patch-outcome-s3-writer<br/>Optional path /platform/<br/>Common archive + enrichment permissions"]
            SSM["SSM Run Command<br/>AWS-RunPatchBaseline*<br/>Scan or Install"]
            subgraph BUS["EventBridge default bus"]
                R1["invocation_success<br/>Success"]
                R2["invocation_failure<br/>Terminal failure / non-delivery statuses"]
                R3["command_failure<br/>Command summaries"]
                RC["Optional canary rule<br/>Enabled when created<br/>custom.patch-canary + detail-type canary"]
            end
            CLI["Operator: manually sends canary"]
            FN["Shared terraform-aws-lambda module<br/>Function: alias-prefix-region-writer<br/>handler.handler / Python 3.13 / 30 seconds"]
            PKG[("Regional member S3 package bucket<br/>prefix-pkg-account-region<br/>SSE-S3 or independent local package CMK")]
            BUILD["Terraform archive + package upload<br/>Unique regional zip name"]
            READS["Bounded enrichment — at most 10 seconds<br/>SSM ListCommandInvocations / ListCommands<br/>SSM agent status / optional EC2 tags"]
            LOGS[("CloudWatch Logs<br/>/aws/lambda/alias-prefix-region-writer<br/>365-day default retention / optional local log CMK")]
            TDLQ[("Shared SQS: target-dlq<br/>EventBridge target delivery failures<br/>Original event + message attributes / 14 days")]
            DEST[("Shared SQS: lambda-dlq<br/>Lambda async on-failure destination<br/>Invocation record + requestPayload / 14 days")]
            RP["Regional IAM policy<br/>Only this function's logs<br/>and its failure-destination queue"]
            SSM --> R1 & R2 & R3
            R1 & R2 & R3 --> FN
            CLI --> RC --> FN
            R1 & R2 & R3 & RC -. delivery failure .-> TDLQ
            FN -. exhausted retries / expired event .-> DEST
            FN --> LOGS
            FN -. optional API reads .-> READS
            BUILD --> PKG --> FN
            ROLE -. execution identity .-> FN
            RP -. attached to .-> ROLE
        end
        SECONDARY["Same module in each additional region<br/>create_writer_role=false<br/>Own Lambda, package bucket, logs, rules and queues<br/>Own regional runtime policy"]
        ROLE -. "writer_role_arn reused" .-> SECONDARY
    end
    subgraph CENTRAL["Existing central account — owned by other teams"]
        POLICY["Existing bucket + KMS policies<br/>Merge rendered statements manually<br/>Actual PrincipalOrgID + full role-path pattern"]
        BUCKET[("Existing archive bucket<br/>patchingsolution-events/outcomes/<br/>Sibling of patchingsolution/")]
        KEY{{"Existing central KMS CMK<br/>For SSE-KMS archives"}}
        INGEST["Existing s3tofirehose ingestion<br/>Verify routing of the outcomes prefix"]
        SPLUNK[("Splunk: aws:ssm:patch:outcome<br/>Schema 2 + action lookup")]
        POLICY -. authorizes .-> BUCKET
        POLICY -. authorizes .-> KEY
        BUCKET -. GenerateDataKey on writer's behalf .-> KEY
        BUCKET --> INGEST --> SPLUNK
    end
    FN ==>|"Cross-account PutObject<br/>SSE-KMS when configured"| BUCKET
    STDOUT[("Existing aws:ssm:patch:stdout")] -. "correlate account + region + command_id + instance_id" .-> SPLUNK
```

## Identity, regions and dependencies

The primary Lambda deployment owns exactly one role and its common S3/KMS/SSM/EC2
policy in `iam.tf`. No separate account module or repository is needed. Its role
name and path are consistent across the fleet. Additional regional deployments
set `create_writer_role=false` and receive the primary output `writer_role_arn`;
each attaches a uniquely named runtime policy for its log group and Lambda failure
destination. Keep common archive/enrichment settings consistent across regions. IAM inline-policy
size limits still apply to the shared role; review policy size when expanding
to many regions.

The shared Lambda and SQS source modules are consumed unchanged. They prefix
names with the member account alias, which must exist and fit AWS name limits.
The Lambda input includes region so the shared module's local zip filenames
also differ in a two-region root. Package buckets are created in each Lambda's
region. Terraform establishes bucket protection/encryption and execution
permissions before making targets available. IAM propagation may still require
AWS retries during deployment.

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

The handler writes flat, newline-terminated JSON with schema version 2,
`event_id`, `operation`, original event identity, status and optional context.
SSM invocation events often omit command parameters, so successful runs may
need a cached `ListCommands` call to distinguish Scan from Install. Metadata
is cached for fifteen seconds per Lambda environment; environments do not
share their caches. S3 failures propagate for Lambda retries.

SSM service events use [best-effort delivery](https://docs.aws.amazon.com/eventbridge/latest/ref/events-ref-ssm.html).
This design has no reconciliation poller: an event never received by EventBridge
cannot be recovered by either queue. Duplicate delivery is possible; repeated
writes use the same event-based key, and Splunk deduplicates event IDs/counts.
A canary proves downstream delivery only after its event is found in Splunk;
it does not prove that real SSM event patterns match.

## Deployment boundary

`rules_enabled` defaults to `false`. Creating the optional canary leaves its
rule enabled, but there is no schedule; an operator sends the event manually.
No custom metrics, alarms, SNS, central resources or bucket notifications are
created. Existing ingestion is reused and its outcomes-prefix routing is verified.
Packages, retained logs, requests, and any KMS usage can incur charges even
while SSM rules are disabled.

Use [BUILD-INSTRUCTIONS-infrastructure.md](BUILD-INSTRUCTIONS-infrastructure.md)
for deployment/tests, [PAYLOAD-SPEC-patch-outcome-record.md](PAYLOAD-SPEC-patch-outcome-record.md)
for the record contract, [central-prerequisites/README.md](central-prerequisites/README.md)
for cross-account access and queue replay, and [splunk/README.md](splunk/README.md)
for parsing, correlation and pilot acceptance.
