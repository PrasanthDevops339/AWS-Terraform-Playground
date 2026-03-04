# simple-sqs-no-tls

Minimal SQS deployment **without** an explicit SecureTransport policy.

This is **Phase 1** of a two-phase testing exercise to confirm that adding an
`aws:SecureTransport = false` deny policy does not break existing workloads.

## What is deployed

| Resource | Purpose |
|---|---|
| `aws_kms_key` | Customer-managed key for SQS encryption at rest |
| `aws_sqs_queue` (main) | Application queue with KMS encryption and DLQ redrive |
| `aws_sqs_queue` (DLQ) | Catches messages that fail processing > 3 times |

No queue policy is attached. SQS endpoints enforce HTTPS at the service level,
so in-transit encryption is already active even without the explicit deny.

## Usage

```bash
terraform init
terraform plan
terraform apply
```

After apply, the outputs include ready-to-run CLI test commands:

```bash
# Send a message
aws sqs send-message \
  --queue-url <queue_url output> \
  --message-body 'hello-from-test' \
  --region us-east-2

# Receive and inspect
aws sqs receive-message \
  --queue-url <queue_url output> \
  --region us-east-2
```

Verify `tlsDetails.tlsVersion` in CloudTrail after sending — you should see
`TLSv1.2` or `TLSv1.3`, confirming the call used TLS even without a deny policy.

## Phase 2

Once baseline traffic is confirmed, switch to `simple-sqs-with-tls` which sets
`enable_secure_transport = true`. The same test commands should continue to
succeed, proving the policy is a no-op for standard SDK/CLI callers.

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
| `secure_transport_policy_enabled` | Policy state (`false` in this project) |
| `test_send_message` | Ready-to-run CLI send command |
| `test_receive_message` | Ready-to-run CLI receive command |

## Cleanup

```bash
terraform destroy
```

