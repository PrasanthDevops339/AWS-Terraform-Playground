# Central prerequisites and delivery recovery

The central bucket, KMS key, policies and existing Splunk ingestion belong to
other teams. This Terraform creates none of those resources and no bucket
notification configuration. The primary Lambda deployment renders statements
for the owners to merge into their existing policies. Existing ingestion is available;
verify its route for the new sibling outcomes prefix.

Examples below use dummy central account `111122223333`, members
`222233334444` / `333344445555`, and organization `o-example1234`. Replace those
values before any live commands. Sample JSON files are illustrative **statements**
except `sample-writer-role-policy.json`, which is a common member IAM policy.
They are not replacements for existing bucket or key policies.

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
region. Skip KMS commands for SSE-S3. Also check the existing ingestion service's
routing/labeling and the reader's S3/KMS permissions for the new prefix.

| Setting | Required writer configuration |
|---|---|
| BucketOwnerEnforced | Prefer `archive_object_acl=null`. An upload with `bucket-owner-full-control` is also accepted; other ACLs fail. |
| ObjectWriter / BucketOwnerPreferred | Coordinate `bucket-owner-full-control`, member `s3:PutObjectAcl` and the corresponding central allowance. Without the ACL, ownership/read access can differ even when the write succeeds. |
| SSE-S3 | Leave `archive_kms_key_arn=null`; the rendered KMS statement is null. |
| SSE-KMS with a customer-managed key | Set the **actual central key ARN** in every regional module call, including when bucket default encryption is already SSE-KMS. |
| SSE-KMS with an AWS-managed key | The central owner must provide a suitable customer-managed key for this cross-account write path. |
| Role path/boundary | Use the actual member role path and required boundary. Both central statements include the complete role path. |

[Bucket ownership documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)
allows no ACL or bucket-owner-full-control on enforced buckets. Do not change
central ownership settings automatically: existing clients may depend on them.
A successful write is not sufficient evidence that the ingestion role can read
or decrypt that object.

## Merge the rendered access statements

From the initialized member root after the primary Lambda deployment (including its IAM role):

```bash
terraform output -json central_prerequisites > central-prerequisites.json
```

The Lambda module requires the actual `organization_id` when creating the role.
The primary deployment's `central_prerequisites` output includes:

- Bucket statement: PutObject on exactly `<bucket>/<prefix>/*`; PutObjectAcl is
  included only when the optional ACL is configured. Conditions restrict the
  actual organization and `arn:<partition>:iam::*:role<path><writer_role_name>`.
  With ACL enabled, the condition also requires bucket-owner-full-control.
- KMS statement: GenerateDataKey/Encrypt/DescribeKey, with the same org and
  full role-path conditions. It is null when no central CMK is configured.

The central owner merges these into the existing policy documents, retaining
administration, readers, AFT statements and explicit protections. Never apply
these output objects as complete replacement policies. Inspect:

| Sample | Purpose |
|---|---|
| `sample-bucket-policy.json` | Writer statement for the default no-ACL path. |
| `sample-bucket-policy-acls-enabled.json` | Writer statement including ACL permission/condition. |
| `sample-kms-key-policy.json` | Writer encryption statement. |
| `sample-kms-key-policy-hardened.json` | Optional ViaService restriction to S3 in the **central bucket/key region**. |
| `sample-writer-role-policy.json` | Illustrative common member IAM policy; regional logs/queue grants are separate. |

S3 calls KMS on the writer's behalf. If adding `kms:ViaService`, use the central
bucket's region even when the Lambda writes from another region, and omit
DescribeKey from that service-only statement. Do not add KMS Decrypt or archive
read/list/delete permissions to the writer. Keep the ingestion reader's existing
Decrypt permissions. A wrong key can produce successful writes that ingestion
cannot decrypt. See [AWS SSE-KMS permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html).

## Explicit Denies and organizational controls

An Allow does not override a Deny. Inspect central policies, SCPs, permission
boundaries, endpoint policies and any required service paths before enabling:

| Restriction | Check |
|---|---|
| `aws:SourceVpce` / `aws:SourceVpc` | This writer has no VPC attachment. An endpoint-only bucket Deny can reject it. Resolve the approved network path before rollout. |
| SSE algorithm/key header | The writer sends explicit SSE-KMS/key headers only when the central key input is set. |
| Account allowlist / organization / role path | Confirm both dummy examples are replaced and the exact writer role path is authorized. |
| Local log/package key conditions | Authorize logs in the member region and the deployment principal's package operations separately. Do not reuse the central archive key. |
| Lambda creation/permissions boundary/VPC guardrails | Confirm the AFT role can provision the regional resources. A required VPC deployment needs an explicit implementation extension; no automatic fallback is provided. |

No second `aws_s3_bucket_notification` is created: that resource is authoritative
for the bucket and could replace the existing ingestion notifications. The
central owner verifies or extends the existing configuration. The sibling prefix
avoids accidental stdout labeling, but must still be included in the ingestion
route under `aws:ssm:patch:outcome`.

## Canary and pilot verification

With SSM rules dormant, run the regional `canary_commands` from the example root
using that member's credentials. Check `FailedEntryCount=0`; save the returned
EventId. The synthetic event is manually sent, and the canary rule is enabled
only when `enable_canary=true`. It cannot demonstrate matching of real SSM events.

Use an authorized central reader to locate
`<prefix>/dt=<UTC date>/<member>/<region>/canary_<EventId>.json`. Verify the JSON
and its encryption/ownership. Use the actual ingestion reader to perform a
GetObject/read/decrypt check where permitted; HeadObject alone does not prove
KMS decryption. Then find `record_type=canary event_id=<EventId>` in Splunk and
confirm the source account/region and event timestamp.

Inspect actual deployed queue settings with:

```bash
aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names MessageRetentionPeriod SqsManagedSseEnabled
```

Expected retention is 1209600 seconds and SSE-SQS enabled. Check both queues and
both regions. Stored packages/logs and requests can incur charges while dormant.

| Symptom | Likely check |
|---|---|
| EventBridge target DLQ | Function permission, target ARN, delivery retries; inspect message attributes. |
| Lambda on-failure destination | Inspect responseContext/responsePayload, then requestPayload and writer logs. |
| S3 AccessDenied | Member and central grants, explicit Denies, ACL permission/condition. |
| KMS AccessDenied | Actual key ARN, org/role path, central-region ViaService condition. |
| AccessControlListNotSupported | An unsupported ACL was supplied to an enforced bucket; null and bucket-owner-full-control uploads are supported. |
| Object exists but is absent from Splunk | Prefix routing, labeling, reader ownership/decrypt access, parsing and ingestion delay. |

## Queue envelopes and replay

These are two different message formats. Inspect one message without deleting it:

```bash
aws sqs receive-message --queue-url QUEUE_URL --max-number-of-messages 1 --message-system-attribute-names All --message-attribute-names All --visibility-timeout 300 > received.json
```

For the **EventBridge target DLQ**, Body contains the original event JSON and
message attributes carry delivery error details. Extract it with:

```bash
jq -r '.Messages[0].Body' received.json > original-event.json
```

For the **Lambda asynchronous on-failure destination**, Body contains an
invocation record, including requestContext, responseContext/responsePayload
and the original event under **requestPayload**:

```bash
jq '.Messages[0].Body | fromjson | .requestPayload' received.json > original-event.json
```

Check the extracted event's source, ID, time, account and region. After fixing
the cause, replay the **original** event directly to its regional writer:

```bash
aws lambda invoke --function-name WRITER_FUNCTION --invocation-type RequestResponse --cli-binary-format raw-in-base64-out --payload fileb://original-event.json replay-response.json
```

Do not send the Lambda failure wrapper to the handler. Do not regenerate the
event ID/time, and do not use PutEvents to impersonate `aws.ssm`. A synchronous
Invoke HTTP success does not prove handler success: inspect `FunctionError` in
the command response and the output JSON, then verify S3/Splunk delivery. Failed
synchronous replay stays the operator's responsibility; it does not use the
function's asynchronous retry configuration.

Only after verification should the operator delete that received queue message
using its current ReceiptHandle. Do not acknowledge it based only on queue
receipt or an HTTP 200. If the receipt expires, receive it again. Replaying
preserves the event-based S3 key, while Splunk deduplicates downstream duplicates.
Use the correct member profile/region for receive/invoke/delete; central reading
uses the separately authorized reader.

There is no automatic queue consumer, redrive workflow, custom alarm or scheduled
canary. Operations must inspect/recover messages before their fourteen-day
retention expires. SSM events never received by EventBridge appear in neither
queue; delivery remains best effort without reconciliation.
