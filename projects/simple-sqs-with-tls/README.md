# simple-sqs-with-tls

SQS deployment **with** an explicit `aws:SecureTransport = false` deny policy.

This is **Phase 2** of a two-phase testing exercise. Deploy this after
`simple-sqs-no-tls` is working and run the same test commands to confirm
nothing breaks when the SecureTransport policy is attached.

## What is deployed

| Resource | Purpose |
|---|---|
| `aws_kms_key` | Customer-managed key for SQS encryption at rest |
| `aws_sqs_queue` (main) | Application queue with KMS encryption and DLQ redrive |
| `aws_sqs_queue` (DLQ) | Catches messages that fail processing > 3 times |
| `aws_sqs_queue_policy` | Denies `sqs:*` when `aws:SecureTransport = false` |

## The only difference from simple-sqs-no-tls

```hcl
# simple-sqs-no-tls
enable_secure_transport = false   # no policy attached

# simple-sqs-with-tls
enable_secure_transport = true    # deny policy attached
```

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Test workflow

### 1. Verify the policy is attached

```bash
aws sqs get-queue-attributes \
  --queue-url <queue_url output> \
  --attribute-names Policy \
  --region us-east-2
```

You should see the deny statement for `aws:SecureTransport = false`.

### 2. Send a message (must still succeed)

```bash
aws sqs send-message \
  --queue-url <queue_url output> \
  --message-body 'hello-with-tls-policy' \
  --region us-east-2
```

This will succeed. The AWS CLI uses HTTPS, so `aws:SecureTransport = true`
and the deny never fires.

### 3. Receive the message (must still succeed)

```bash
aws sqs receive-message \
  --queue-url <queue_url output> \
  --region us-east-2
```

### 4. Confirm TLS in CloudTrail

Search CloudTrail for the above events:

```
eventSource = "sqs.amazonaws.com"
AND eventName IN ("SendMessage", "ReceiveMessage")
```

Each event should contain `tlsDetails.tlsVersion = TLSv1.2` or `TLSv1.3`.

### 5. Check for any AccessDenied errors

```
eventSource = "sqs.amazonaws.com"
AND errorCode = "AccessDenied"
```

You should find zero events. If you do find any, inspect `userAgent` and
`sourceIPAddress` to identify the caller that isn't using HTTPS.

## Why this policy is safe for standard workloads

| Caller type | Uses HTTPS? | Effect of policy |
|---|---|---|
| AWS CLI | Yes | No change |
| boto3 / Python SDK | Yes | No change |
| Java / Go / Node SDK | Yes | No change |
| Terraform AWS provider | Yes | No change |
| VPC interface endpoint (PrivateLink) | Yes | No change |
| Custom HTTP client over plain HTTP | No | AccessDenied (expected) |

## Inputs

| Name | Default | Description |
|---|---|---|
| `aws_region` | `us-east-2` | AWS region |
| `environment` | `dev` | Environment tag |
| `project_name` | `simple-sqs` | Prefix for resource names |
| `tags` | `{}` | Additional tags |

## Outputs

| Name | Description |
|---|---|
| `queue_url` | SQS queue URL |
| `queue_arn` | SQS queue ARN |
| `queue_name` | SQS queue name |
| `dlq_url` | Dead letter queue URL |
| `dlq_arn` | Dead letter queue ARN |
| `kms_key_arn` | KMS key ARN |
| `secure_transport_policy_enabled` | Policy state (`true` in this project) |
| `test_send_message` | Ready-to-run CLI send command |
| `test_receive_message` | Ready-to-run CLI receive command |
| `verify_policy` | CLI command to inspect the queue policy |

## Cleanup

```bash
terraform destroy
```
