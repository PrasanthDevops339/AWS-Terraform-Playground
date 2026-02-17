# Test Cases — simple-sqs-no-tls

**Test file**: `test_sqs.py`
**Type**: Integration tests (requires `terraform apply` + AWS credentials)
**Phase**: 1 of 2 — baseline before SecureTransport policy

---

## How to Run

```bash
# Install dependency
pip install -r tests/requirements.txt

# Run tests (reads terraform outputs automatically)
cd projects/simple-sqs-no-tls
python3 tests/test_sqs.py

# Override queue URL without terraform (CI/CD or manual)
QUEUE_URL=https://sqs.us-east-2.amazonaws.com/<account-id>/<queue-name> \
DLQ_URL=https://sqs.us-east-2.amazonaws.com/<account-id>/<queue-name>-dlq \
AWS_REGION=us-east-2 \
python3 tests/test_sqs.py
```

---

## Test Cases

### TC-01 — Queue exists and is reachable

| | |
|---|---|
| **ID** | TC-01 |
| **Name** | Queue exists and is reachable |
| **Function** | `test_01_queue_exists` |
| **Type** | Smoke |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Calls `GetQueueAttributes` with `AttributeNames=["All"]` on the queue URL from Terraform output. Asserts the response is non-empty.

**Pass condition**: API returns a non-empty attributes dict.

**Fail means**: Queue was not created, wrong queue URL, or insufficient IAM permissions.

---

### TC-02 — KMS encryption at rest is configured

| | |
|---|---|
| **ID** | TC-02 |
| **Name** | KMS encryption at rest is configured |
| **Function** | `test_02_encryption_at_rest_enabled` |
| **Type** | Configuration |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Reads `KmsMasterKeyId` attribute. Asserts:
- The attribute is non-empty (some key is set)
- The key is NOT `alias/aws/sqs` (the AWS-managed default — a customer-managed key is required)

**Pass condition**: `KmsMasterKeyId` is a non-empty string that is not `alias/aws/sqs`.

**Fail means**: `kms_master_key_id` was not passed to the module, or the KMS key was not created.

**Expected value**: The ARN or alias of the KMS key from `terraform output kms_key_arn`.

---

### TC-03 — Long polling configured (receive wait = 20s)

| | |
|---|---|
| **ID** | TC-03 |
| **Name** | Long polling configured |
| **Function** | `test_03_long_polling_configured` |
| **Type** | Configuration |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Reads `ReceiveMessageWaitTimeSeconds`. Asserts the value is exactly `20`.

**Pass condition**: `ReceiveMessageWaitTimeSeconds == 20`

**Fail means**: `receive_wait_time_seconds` in `main.tf` was not set to 20, or the module did not apply the value.

**Why this matters**: Long polling (20s) eliminates empty receive responses and reduces SQS API costs significantly compared to short polling (0s).

---

### TC-04 — Message retention is 4 days

| | |
|---|---|
| **ID** | TC-04 |
| **Name** | Message retention is 4 days |
| **Function** | `test_04_message_retention_period` |
| **Type** | Configuration |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Reads `MessageRetentionPeriod`. Asserts the value is `345600` (60 × 60 × 24 × 4 = 345,600 seconds = 4 days).

**Pass condition**: `MessageRetentionPeriod == 345600`

**Fail means**: `message_retention_seconds` variable mismatch.

---

### TC-05 — DLQ redrive policy is configured

| | |
|---|---|
| **ID** | TC-05 |
| **Name** | DLQ redrive policy is configured |
| **Function** | `test_05_dlq_configured` |
| **Type** | Configuration |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Reads the `RedrivePolicy` attribute (a JSON string). Parses it and asserts:
- `deadLetterTargetArn` key is present and non-empty
- `maxReceiveCount` equals `3`

**Pass condition**: Both assertions hold.

**Fail means**: `enable_dlq = false` in the module call, or DLQ creation failed.

**Why maxReceiveCount=3**: A message that fails processing 3 times moves to the DLQ for investigation. Too low (1) could cause false positives; too high (10+) wastes retries on poison-pill messages.

---

### TC-06 — No SecureTransport deny policy attached

| | |
|---|---|
| **ID** | TC-06 |
| **Name** | No SecureTransport deny policy attached |
| **Function** | `test_06_no_secure_transport_deny_policy` |
| **Type** | Security / State |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Reads the `Policy` attribute.
- If empty: passes immediately (no policy = no deny)
- If a policy exists: parses each Deny statement's Condition block looking for `aws:SecureTransport = "false"`

**Pass condition**: No Deny statement with a SecureTransport condition is found.

**Fail means**: The wrong project was applied (`simple-sqs-with-tls` instead of `simple-sqs-no-tls`), or a manual policy was attached outside of Terraform.

**Why this is tested**: This is the exact boundary that separates Phase 1 from Phase 2. It is important to confirm the baseline has no deny before adding one — otherwise you cannot attribute any behaviour change to the policy addition.

---

### TC-07 — SendMessage succeeds

| | |
|---|---|
| **ID** | TC-07 |
| **Name** | SendMessage succeeds |
| **Function** | `test_07_send_message` |
| **Type** | Functional |
| **AWS API** | `sqs:SendMessage` |

**What it does**: Sends a message with a unique UUID body via `boto3.send_message`. Asserts:
- HTTP status code is `200`
- Response contains a non-empty `MessageId`

**Pass condition**: Both assertions hold.

**Side effect**: Stores the message body in a module-level variable so TC-08 can verify round-trip.

**Fail means**: IAM permissions missing, KMS key access denied, or queue does not exist.

---

### TC-08 — ReceiveMessage returns the sent message

| | |
|---|---|
| **ID** | TC-08 |
| **Name** | ReceiveMessage returns the sent message |
| **Function** | `test_08_receive_message` |
| **Type** | Functional / Round-trip |
| **AWS API** | `sqs:ReceiveMessage` |

**What it does**: Waits 1 second (propagation), then polls for messages with `WaitTimeSeconds=5`. Asserts:
- At least one message is returned
- The returned message body matches the UUID body sent in TC-07

**Pass condition**: Body matches.

**Side effect**: Stores the `ReceiptHandle` for TC-09.

**Fail means**: Message was not received — possible if another consumer already consumed it, or a very unusual propagation delay.

---

### TC-09 — DeleteMessage cleans up

| | |
|---|---|
| **ID** | TC-09 |
| **Name** | DeleteMessage cleans up |
| **Function** | `test_09_delete_message` |
| **Type** | Functional / Cleanup |
| **AWS API** | `sqs:DeleteMessage` |

**What it does**: Deletes the received message using the `ReceiptHandle` captured in TC-08. Asserts HTTP status `200`.

**Pass condition**: Delete returns `200`.

**Fail means**: Receipt handle expired (visibility timeout elapsed), or TC-08 did not capture the handle.

---

### TC-10 — DLQ is accessible with 14-day retention

| | |
|---|---|
| **ID** | TC-10 |
| **Name** | DLQ is accessible with 14-day retention |
| **Function** | `test_10_dlq_accessible` |
| **Type** | Configuration |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Calls `GetQueueAttributes` on the DLQ URL. Asserts `MessageRetentionPeriod == 1209600` (14 days).

**Pass condition**: `1209600` matches.

**Fail means**: DLQ was not created (`enable_dlq = false`), or `dlq_message_retention_seconds` was not passed correctly.

**Why 14 days**: Messages that land in the DLQ represent processing failures. Engineers need enough time to investigate and replay them. 14 days gives two full work-weeks.

---

## Test Execution Order

Tests are numbered and designed to run sequentially. TC-07 through TC-09 form a send → receive → delete pipeline and depend on each other's side effects:

```
TC-01  (smoke)
TC-02  (config)
TC-03  (config)
TC-04  (config)
TC-05  (config)
TC-06  (security state)
TC-07 → TC-08 → TC-09  (functional pipeline — order matters)
TC-10  (config)
```

---

## Pass / Fail Criteria

The test suite exits `0` only when all 10 tests pass.

| Outcome | Exit code | Next action |
|---|---|---|
| All 10 passed | `0` | Proceed to `simple-sqs-with-tls` |
| Any failed | `1` | Fix before proceeding — baseline must be clean |

---

## Relationship to Console Testing

These automated tests cover the same ground as the manual steps in `CONSOLE-TESTING-GUIDE.md`, but faster and repeatable:

| Console step | Automated test |
|---|---|
| Queue visible | TC-01 |
| Encryption tab | TC-02 |
| Configuration tab (wait time) | TC-03 |
| Configuration tab (retention) | TC-04 |
| Dead-letter queue tab | TC-05 |
| Access policy tab (empty) | TC-06 |
| Send and receive messages | TC-07, TC-08, TC-09 |
| DLQ accessible | TC-10 |

---

**Last Updated**: 2026-02-17
**Status**: Phase 1 — Baseline
