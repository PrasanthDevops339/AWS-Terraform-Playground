# AWS Console Testing Guide — simple-sqs-no-tls

**Project**: `simple-sqs-no-tls`
**Purpose**: Verify the baseline SQS deployment works correctly **before** adding the SecureTransport deny policy
**Phase**: 1 of 2 — establish a clean baseline, record what normal traffic looks like

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Terraform applied | `terraform apply` completed successfully in `simple-sqs-no-tls/` |
| AWS Console access | IAM permissions for `sqs:*`, `kms:Describe*`, `cloudtrail:LookupEvents` |
| Region | `us-east-2` (Ohio) — unless you changed `aws_region` variable |

Get your queue URL before starting:

```bash
cd projects/simple-sqs-no-tls
terraform output queue_url
terraform output dlq_url
terraform output kms_key_arn
```

---

## Phase 1 — Verify Queue Exists and Configuration (5 min)

### Step 1.1 — Navigate to SQS Console

1. Open AWS Console → search **"SQS"** in the top search bar
2. Select **"Simple Queue Service"**
3. Confirm region is **us-east-2** (top-right dropdown)

### Step 1.2 — Find Your Queue

1. In the queue list, search for your queue name:
   - Pattern: `<account-alias>-simple-sqs-dev-orders`
   - Example: `mycompany-simple-sqs-dev-orders`
2. Click the queue name to open the details page

### Step 1.3 — Verify Queue Attributes

Click the **"Configuration"** tab and confirm:

| Attribute | Expected Value | Why |
|---|---|---|
| Visibility timeout | 30 seconds | Messages locked for 30s during processing |
| Message retention period | 4 days | 345,600 seconds |
| Delivery delay | 0 seconds | No delay on message delivery |
| Maximum message size | 256 KB | 262,144 bytes |
| Receive message wait time | 20 seconds | Long polling — reduces empty responses and cost |

### Step 1.4 — Verify Encryption

Click the **"Encryption"** tab and confirm:

| Setting | Expected |
|---|---|
| Server-side encryption | Enabled |
| Encryption key type | Customer managed key (CMK) |
| KMS key ARN | Matches `terraform output kms_key_arn` |

> If you see "SQS managed encryption key" — KMS was not applied correctly. Check the `kms_master_key_id` variable in `main.tf`.

### Step 1.5 — Verify Dead Letter Queue

Click the **"Dead-letter queue"** tab and confirm:

| Setting | Expected |
|---|---|
| Dead-letter queue | Enabled |
| Dead-letter queue URL | Points to `<name>-dlq` |
| Maximum receives | 3 |

> This means: if a consumer fails to process a message 3 times, it moves to the DLQ.

### Step 1.6 — Verify Access Policy (Should Be Empty)

Click the **"Access policy"** tab.

**Expected**: The policy is either blank or shows the AWS default.

**What you should NOT see**: Any `Deny` statement referencing `aws:SecureTransport`.

> This is the key difference from `simple-sqs-with-tls`. No explicit deny exists here. Transport encryption is still active (SQS only accepts HTTPS endpoints), but there is no IAM-layer policy enforcement.

---

## Phase 2 — Send a Test Message (5 min)

### Step 2.1 — Open Send and Receive Messages

On your queue's detail page, click **"Send and receive messages"** (top-right button).

### Step 2.2 — Send a Message

In the **"Send message"** panel:

1. **Message body**: Enter a test message, e.g.:
   ```
   {"event":"test","source":"console","phase":"no-tls-baseline","timestamp":"2026-02-17"}
   ```
2. **Delivery delay**: Leave at `0`
3. Click **"Send message"**

**Expected result**: Green success banner — `"Message sent successfully"`

> Note the `Message ID` shown — you can cross-reference this in CloudTrail.

### Step 2.3 — Verify the Message Count

After sending, check the **"Details"** tab of the queue:

| Counter | Expected |
|---|---|
| Messages available | 1 (or more if you sent multiple) |
| Messages in flight | 0 |
| Messages delayed | 0 |

---

## Phase 3 — Receive and Delete the Message (5 min)

### Step 3.1 — Poll for Messages

In the **"Receive messages"** panel (lower half of "Send and receive messages"):

1. Click **"Poll for messages"**
2. Wait up to 20 seconds (long polling is set to 20s)
3. Your test message should appear in the **"Messages"** table

### Step 3.2 — Inspect the Message

Click the **Message ID** link in the results table:

| Field | Check |
|---|---|
| Body | Matches what you sent |
| Message ID | Unique UUID |
| Receive count | 1 |
| Sent at | Timestamp of when you sent it |

### Step 3.3 — Delete the Message

1. Select the checkbox next to your message
2. Click **"Delete"**
3. Confirm deletion

**Expected**: Message disappears from the table. The queue counter returns to 0.

---

## Phase 4 — Verify the DLQ (5 min)

### Step 4.1 — Navigate to the DLQ

Go back to the SQS queue list and find:
- `<account-alias>-simple-sqs-dev-orders-dlq`

### Step 4.2 — Check DLQ Configuration

Click **"Configuration"** tab:

| Attribute | Expected |
|---|---|
| Message retention period | 14 days (1,209,600 seconds) |
| Server-side encryption | Enabled (same KMS key) |

> The DLQ retains messages longer than the main queue so engineers have time to investigate failures.

### Step 4.3 — Confirm DLQ is Empty

Click **"Send and receive messages"** → **"Poll for messages"**

**Expected**: No messages. (Nothing has failed 3 times yet.)

---

## Phase 5 — Monitor Tab and Metrics (5 min)

On the main queue's detail page, click the **"Monitoring"** tab:

| Metric to check | What it tells you |
|---|---|
| NumberOfMessagesSent | Should show a spike from your send test |
| NumberOfMessagesReceived | Should show a spike from your receive test |
| NumberOfMessagesDeleted | Should reflect your delete |
| ApproximateNumberOfMessagesVisible | Should be 0 after cleanup |
| NumberOfEmptyReceives | May show some — long polling reduces these |

> CloudWatch metrics update every minute. Wait 1–2 minutes after testing if you see zeros.

---

## Phase 6 — CloudTrail Verification (10 min)

This is the **detective work** step — confirming that calls used TLS even without an explicit deny policy.

### Step 6.1 — Navigate to CloudTrail

AWS Console → **"CloudTrail"** → **"Event history"**

Set the filter:
- **Attribute**: Event source
- **Value**: `sqs.amazonaws.com`

### Step 6.2 — Find Your SendMessage Event

Look for `SendMessage` events with your queue name in the `requestParameters`.

Click a `SendMessage` event and expand the record. Look for:

```json
"tlsDetails": {
  "tlsVersion": "TLSv1.2",
  "cipherSuite": "ECDHE-RSA-AES128-GCM-SHA256"
}
```

**What this proves**: Even without a deny policy, the console-initiated call used TLS. The SQS endpoint enforces HTTPS at the service level.

### Step 6.3 — Check for AccessDenied Events

Filter by:
- **Attribute**: Error code
- **Value**: `AccessDenied`

With the source filter still on `sqs.amazonaws.com`.

**Expected**: Zero results.

> If you see AccessDenied here on anything other than intentional permission issues, investigate before proceeding to Phase 2.

### Step 6.4 — CloudTrail CLI Equivalent

```bash
# View recent SQS events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=sqs.amazonaws.com \
  --max-results 20 \
  --region us-east-2 \
  | jq '.Events[] | {EventName, EventTime, Username: .Username}'

# Check for any AccessDenied on SQS
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=sqs.amazonaws.com \
  --max-results 50 \
  --region us-east-2 \
  | jq '.Events[] | select(.CloudTrailEvent | fromjson | .errorCode == "AccessDenied")'
```

**Expected output for AccessDenied query**: Empty array `[]`

---

## Phase 7 — KMS Console Verification (5 min)

### Step 7.1 — Navigate to KMS

AWS Console → **"Key Management Service"** → **"Customer managed keys"**

Find your key: `<account-alias>-simple-sqs-dev-sqs-key`

### Step 7.2 — Check Key Details

| Field | Expected |
|---|---|
| Status | Enabled |
| Key type | Symmetric |
| Key usage | Encrypt and decrypt |
| Key rotation | Enabled (auto-rotated annually) |

### Step 7.3 — Confirm Key Policy

Click the **"Key policy"** tab — you should see a statement named `SQSServicePermissions` that allows `sqs.amazonaws.com` to use the key for encryption/decryption.

---

## Expected Results Summary

| Test | Expected Result | Fail if... |
|---|---|---|
| Queue visible in console | Yes | Terraform apply failed |
| Encryption type | Customer KMS (not SQS default) | `kms_master_key_id` not set |
| Retention | 4 days | Config mismatch |
| Long polling | 20 seconds | Config mismatch |
| DLQ configured | Yes, maxRetry=3 | `enable_dlq = false` |
| Access policy | Empty / no deny | Wrong project deployed |
| Send message | Success | IAM permissions missing |
| Receive message | Returns sent message | Message retention issue |
| CloudTrail TLS | `tlsVersion: TLSv1.2` or `TLSv1.3` | Very unusual — investigate |
| CloudTrail AccessDenied | Zero results | Unexpected — investigate |

---

## Troubleshooting

### Queue not visible in console

❌ **Issue**: Queue name doesn't appear in the SQS list

✅ **Fix**:
```bash
# Confirm apply completed
cd projects/simple-sqs-no-tls && terraform show | grep queue_name
# Confirm correct region
aws sqs list-queues --region us-east-2
```

### Message not received after polling

❌ **Issue**: Polling returns no messages

✅ **Check**:
1. Visibility timeout — message might be "in flight" if receive was started elsewhere
2. `ApproximateNumberOfMessagesVisible` counter on the queue
3. Confirm you're on the right queue (not the DLQ)

### KMS key not found in console

❌ **Issue**: Key not visible in KMS console

✅ **Fix**:
```bash
# Check key was created
aws kms list-aliases --region us-east-2 | grep simple-sqs
```

### CloudTrail events missing

❌ **Issue**: No SQS events in CloudTrail

✅ **Check**:
1. CloudTrail trail is enabled in `us-east-2`
2. Events take 5–15 minutes to appear in Event history
3. Correct region selected in CloudTrail console

---

## Next Step — Phase 2 Testing

Once all checks above pass, proceed to `simple-sqs-with-tls/` to add the SecureTransport policy and verify it does not break anything.

```bash
cd ../simple-sqs-with-tls
terraform apply
```

Then follow: `simple-sqs-with-tls/CONSOLE-TESTING-GUIDE.md`

---

## Files Reference

| File | Purpose |
|---|---|
| `main.tf` | Infrastructure definition |
| `variables.tf` | Input variables |
| `outputs.tf` | Terraform outputs (queue URL, DLQ URL, etc.) |
| `tests/test_sqs.py` | Automated integration tests |
| `tests/TEST-CASES.md` | Test case documentation |
| `CONSOLE-TESTING-GUIDE.md` | This file |

---

**Last Updated**: 2026-02-17
**Status**: Phase 1 — Baseline (no SecureTransport policy)

