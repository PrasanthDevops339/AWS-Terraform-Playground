# Architecture Diagram

Deployed once per region, per member account (~450 accounts via AFT). The
central account (right side) is owned by another team and is never
created or modified by this module — only referenced.

```mermaid
flowchart TB
    subgraph MEMBER["Member account (× ~450, via AFT)"]
        direction TB

        SSM["SSM Run Command<br/>AWS-RunPatchBaseline"]

        subgraph BUS["EventBridge — default bus"]
            R1["rule: invocation_success<br/>status = Success"]
            R2["rule: invocation_failure<br/>Failed / TimedOut / Cancelled /<br/>Undeliverable / Terminated"]
            R3["rule: command_failure<br/>Failed / Incomplete / AccessDenied / ..."]
            RC["rule: canary (always ON)<br/>source = custom.patch-canary"]
        end

        LAMBDA["Lambda: patch-outcome-writer<br/>src/handler.py<br/>role: patch-outcome-s3-writer"]

        TDLQ[("SQS: target-dlq<br/>EventBridge could not invoke Lambda")]
        LDLQ[("SQS: lambda-dlq<br/>Lambda ran and threw")]

        LOGS[("CloudWatch Logs<br/>/aws/lambda/patch-outcome-writer")]

        SSM -->|status-change event| R1
        SSM -->|status-change event| R2
        SSM -->|status-change event| R3

        R1 -->|invoke| LAMBDA
        R2 -->|invoke| LAMBDA
        R3 -->|invoke| LAMBDA
        RC -->|invoke| LAMBDA

        R1 -.->|invoke failed| TDLQ
        R2 -.->|invoke failed| TDLQ
        R3 -.->|invoke failed| TDLQ
        RC -.->|invoke failed| TDLQ

        LAMBDA -.->|function threw| LDLQ
        LAMBDA --> LOGS
    end

    subgraph CENTRAL["Central account — owned by another team, never created/modified here"]
        direction TB
        BUCKET[("S3 bucket<br/>patchingsolution-events/outcomes/*<br/>(sibling of patchingsolution/)")]
        KMS{{"KMS CMK<br/>encrypts bucket"}}
        POLICY["Bucket policy + KMS key policy<br/>ArnLike role/patch-outcome-s3-writer<br/>+ PrincipalOrgID"]
        FIREHOSE["s3tofirehose ingestion<br/>(owned by another team)"]
        SPLUNK[("Splunk<br/>sourcetype: aws:ssm:patch:outcome")]

        POLICY -.authorizes.-> BUCKET
        BUCKET --> FIREHOSE --> SPLUNK
    end

    LAMBDA ==>|s3:PutObject<br/>SSE-KMS| BUCKET
    LAMBDA -.->|kms:Encrypt /<br/>GenerateDataKey| KMS

    STDOUT[("Existing sourcetype<br/>aws:ssm:patch:stdout")] -.join on command_id.- SPLUNK

    classDef dormant stroke-dasharray: 4 3;
    class TDLQ,LDLQ dormant
```

## Reading the diagram

- **Solid arrows** are the happy path: SSM event → rule → Lambda → S3 →
  Firehose → Splunk.
- **Dashed arrows** are the failure/side paths: a target DLQ catches
  EventBridge-can't-reach-Lambda, a Lambda DLQ catches
  Lambda-ran-and-threw, and the canary proves the whole chain without
  needing a real SSM event.
- The **only cross-account call** is the Lambda's `s3:PutObject` (and the
  paired KMS encrypt calls) into the central bucket — everything else stays
  inside the member account.
- Nothing in the `CENTRAL` box is created by this Terraform module. The
  module only *renders* the two policy statements
  (`central_prerequisites` output) that the bucket owner merges by hand.
- `rules_enabled = false` disables `R1`/`R2`/`R3` (dashed in a live diagram
  would represent "DISABLED state"); `RC` (the canary) always stays
  `ENABLED` regardless.

See `HOW-IT-WORKS.md` for the narrative walkthrough of each step, and
`PAYLOAD-SPEC-patch-outcome-record.md` for what actually lands in the
bucket.
