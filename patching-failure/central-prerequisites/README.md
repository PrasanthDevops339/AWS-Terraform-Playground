# Central prerequisites and delivery recovery

The central bucket, KMS key, policies and existing Splunk ingestion belong to
other teams. This Terraform creates none of them and no bucket notification
configuration. The POC root renders statements for the owners to merge into
their existing policies. Verify that existing ingestion routes the new sibling
outcomes prefix.

Examples below use dummy central account `111122223333`, POC account
`222233334444`, and organization `o-example1234`. Replace them before running any
live commands. The sample JSON files are illustrative **statements**, except
`sample-writer-role-policy.json`, which is an IAM policy for the writer role.
None of them replaces an existing bucket or key policy.

## Owner preflight

Use the central owner's read-only credentials to inspect the actual settings:

```bash
aws s3api get-bucket-location --bucket CENTRAL_BUCKET
aws s3api get-bucket-ownership-controls --bucket CENTRAL_BUCKET
aws s3api get-bucket-encryption --bucket CENTRAL_BUCKET
aws s3api get-bucket-policy --bucket CENTRAL_BUCKET --query Policy --output text
aws s3api get-bucket-notification-configuration --bucket CENTRAL_BUCKET
aws kms get-key-policy --key-id CENTRAL_KEY_ARN --policy-name default --query Policy --output text
```

`get-bucket-location` returns null for us-east-1. Run KMS inspection in the key's
region, and skip the KMS commands for SSE-S3. Also check the existing ingestion
service's routing and labeling, and the reader's S3/KMS permissions for the new
prefix.

| Setting | Required writer configuration |
|---|---|
| BucketOwnerEnforced | Prefer `archive_object_acl=null`. An upload with `bucket-owner-full-control` is also accepted; other ACLs fail. |
| ObjectWriter / BucketOwnerPreferred | Coordinate `bucket-owner-full-control`, the writer's `s3:PutObjectAcl` and the matching central allowance. Without the ACL, ownership and read access can differ even when the write succeeds. |
| SSE-S3 | Leave `archive_kms_key_arn=null`; the rendered KMS statement is null. |
| SSE-KMS with a customer-managed key | Set the **actual central key ARN**, even when the bucket's default encryption is already SSE-KMS. |
| SSE-KMS with an AWS-managed key | The central owner must provide a customer-managed key for this cross-account write path. |
| Role path/boundary | Use the actual role path and any required boundary. Both central statements include the complete role path. |

The [bucket ownership documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)
allows either no ACL or bucket-owner-full-control on enforced buckets. Do not
change central ownership settings automatically, because existing clients may
depend on them. A successful write does not prove that the ingestion role can
read or decrypt the object.

## Merge the rendered access statements

From the applied POC root:

```bash
terraform output -json central_prerequisites > central-prerequisites.json
```

- Bucket statement: PutObject on exactly `<bucket>/<prefix>/*`. PutObjectAcl is
  included only when the optional ACL is configured. Conditions restrict the
  actual organization and `arn:<partition>:iam::*:role<path><writer_role_name>`.
  With the ACL enabled, the condition also requires bucket-owner-full-control.
- KMS statement: GenerateDataKey, Encrypt and DescribeKey, with the same
  organization and full role-path conditions. It is null when no central CMK is
  configured.

The central owner merges these into the existing policy documents and keeps the
administration, reader and other statements and their explicit protections.
Never apply these output objects as complete replacement policies.

| Sample | Purpose |
|---|---|
| `sample-bucket-policy.json` | Writer statement for the default no-ACL path. |
| `sample-bucket-policy-acls-enabled.json` | Writer statement including ACL permission/condition. |
| `sample-kms-key-policy.json` | Writer encryption statement. |
| `sample-kms-key-policy-hardened.json` | Optional ViaService restriction to S3 in the **central bucket/key region**. |
| `sample-writer-role-policy.json` | Illustrative writer archive/enrichment policy; the logs grant is separate. |

S3 calls KMS on the writer's behalf. If you add `kms:ViaService`, use the central
bucket's region even when the Lambda writes from another region, and omit
DescribeKey from that service-only statement. Do not give the writer KMS Decrypt
or any archive read, list or delete permission. Keep the ingestion reader's
existing Decrypt permissions: with the wrong key, writes can succeed while
ingestion cannot decrypt them. See [AWS SSE-KMS permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html).

## Explicit Denies and organizational controls

An Allow does not override a Deny. Before enabling the rules, inspect central
policies, SCPs, permission boundaries, endpoint policies and any required
service paths:

| Restriction | Check |
|---|---|
| `aws:SourceVpce` / `aws:SourceVpc` | The writer has no VPC attachment, so an endpoint-only bucket Deny can reject it. Agree an approved network path first. |
| SSE algorithm/key header | The writer sends explicit SSE-KMS and key headers only when the central key input is set. |
| Account allowlist / organization / role path | Confirm the dummy values are replaced and the exact writer role path is authorized. |
| Local log/package key conditions | Authorize logs and the deployment principal's package operations separately. Do not reuse the central archive key. |
| Lambda creation / permissions boundary / VPC guardrails | Confirm the deploying credentials can create these resources. A mandated VPC deployment needs an explicit code change. |

No second `aws_s3_bucket_notification` is created: that resource is authoritative
for the bucket and could replace the existing ingestion notifications. The central
owner verifies or extends the existing configuration. The sibling prefix avoids
accidental stdout labeling, but it must still be included in the ingestion route
under `aws:ssm:patch:outcome`.

## Canary verification

With the SSM rules dormant, run `terraform output -raw canary_command` using the
POC account's credentials. Check `FailedEntryCount=0` and save the returned
EventId. The canary is a synthetic, manually sent event, so it cannot show that
real SSM events match the rules.

Using an authorized central reader, locate
`<prefix>/dt=<UTC date>/<account>/<region>/canary_<EventId>.json`. Verify the
JSON and its encryption and ownership. Where permitted, have the actual
ingestion reader perform a GetObject/read/decrypt check; HeadObject alone does
not prove KMS decryption. Then find `record_type=canary event_id=<EventId>` in
Splunk and confirm the source account, region and event timestamp.

| Symptom | Likely check |
|---|---|
| EventBridge `FailedInvocations` > 0 | Lambda resource policy (allowed_triggers), target ARN, throttling. |
| Lambda `Errors` / log shows S3 AccessDenied | Writer grants, central bucket statement, explicit Denies, ACL permission/condition. |
| Log shows KMS AccessDenied | Actual key ARN, org/role path, central-region ViaService condition. |
| AccessControlListNotSupported | An unsupported ACL was sent to an enforced bucket; only null and bucket-owner-full-control are supported. |
| Lambda `AsyncEventsDropped` > 0 | Retries or six-hour age exhausted; recover from logs (below). |
| Object exists but is absent from Splunk | Prefix routing, labeling, reader ownership/decrypt access, parsing and ingestion delay. |

## Replay from logs (basic path)

Without the DLQ enhancement, no failed event is stored. The handler logs the
full record on success, and Lambda logs the exception on failure. To replay:

1. Rebuild the original EventBridge event from the log lines or the SSM command.
   It needs the original `source`, `detail-type`, `id`, `time`, `account`,
   `region` and `detail`. Save it as `original-event.json`.
2. After fixing the cause, invoke the writer synchronously:

   ```bash
   aws lambda invoke --function-name WRITER_FUNCTION --invocation-type RequestResponse --cli-binary-format raw-in-base64-out --payload fileb://original-event.json replay-response.json
   ```

3. Check `FunctionError` in the command response and the output JSON, then
   verify delivery in S3 and Splunk. An HTTP 200 does not prove the handler
   succeeded.

Do not regenerate the event ID or time, and do not use PutEvents to impersonate
`aws.ssm`. Replaying keeps the event-based S3 key, and Splunk deduplicates.

## Enhancement (not deployed): queue envelopes and replay

This section applies only after the `ENHANCEMENT (DLQ)` blocks in `main.tf`,
`iam.tf` and `outputs.tf` are uncommented.

Check the queue settings with:

```bash
aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names MessageRetentionPeriod SqsManagedSseEnabled
```

Expect retention of 1209600 seconds and SSE-SQS enabled. The two queues use
different message formats. To inspect one message without deleting it:

```bash
aws sqs receive-message --queue-url QUEUE_URL --max-number-of-messages 1 --message-system-attribute-names All --message-attribute-names All --visibility-timeout 300 > received.json
```

In the **EventBridge target DLQ**, the Body is the original event JSON, and
message attributes carry the delivery error details:

```bash
jq -r '.Messages[0].Body' received.json > original-event.json
```

In the **Lambda asynchronous on-failure destination**, the Body is an invocation
record, with the original event under **requestPayload**:

```bash
jq '.Messages[0].Body | fromjson | .requestPayload' received.json > original-event.json
```

Replay the extracted original event with the synchronous invoke above. Never
send the Lambda failure wrapper to the handler. Delete the received message
using its current ReceiptHandle, and only after S3 and Splunk delivery is
verified. There is no automatic queue consumer or redrive workflow. Messages
must be recovered within the fourteen-day retention, and SSM events that never
reached EventBridge appear in neither queue.
