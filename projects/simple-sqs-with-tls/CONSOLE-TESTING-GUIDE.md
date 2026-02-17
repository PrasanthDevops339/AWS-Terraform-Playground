# AWS Console Testing Guide — simple-sqs-with-tls

**Project**: `simple-sqs-with-tls`
**Purpose**: Verify that adding `aws:SecureTransport=false` deny policy does NOT break normal SQS operations
**Phase**: 2 of 2 — the critical proof-point before rolling out to all queues

> **Run simple-sqs-no-tls first.** This guide assumes you have already completed the Phase 1 baseline in `simple-sqs-no-tls/CONSOLE-TESTING-GUIDE.md` and all tests passed.

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Phase 1 complete | All `simple-sqs-no-tls` tests passed |
| Terraform applied | `terraform apply` completed in `simple-sqs-with-tls/` |
| AWS Console access | `sqs:*`, `kms:Describe*`, `cloudtrail:LookupEvents` |
| Region | `us-east-2` (Ohio) |

```bash
cd projects/simple-sqs-with-tls
terraform output queue_url
terraform output dlq_url
terraform output kms_key_arn
terraform output secure_transport_policy_enabled   # must show: true
```

---

## Phase 1 — Verify the SecureTransport Policy Is Attached (5 min)

This is the first thing to confirm — the entire point of this project.

### Step 1.1 — Navigate to SQS Console

AWS Console → **"Simple Queue Service"** → confirm region **us-east-2**

### Step 1.2 — Find Your Queue

Search for `<account-alias>-simple-sqs-dev-orders` (same name pattern as no-tls).

> If both projects are deployed simultaneously, they will have different queue names because the account alias is the same but the names are identical — consider using different `project_name` variable values if testing both side-by-side.

### Step 1.3 — Open the Access Policy Tab

Click the queue name → **"Access policy"** tab.

**Expected**: A JSON policy document is visible.

Copy the policy and confirm it contains exactly this structure:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyNonSecureTransport",
      "Effect": "Deny",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "sqs:*"
      ],
      "Resource": "arn:aws:sqs:us-east-2:<account-id>:<queue-name>",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Checklist — verify each field**:

| Field | Expected Value | Risk if wrong |
|---|---|---|
| `Effect` | `Deny` | `Allow` would do nothing |
| `Principal.AWS` | `*` | Scoped principal leaves gaps |
| `Action` | `sqs:*` | Narrow actions leave gaps |
| `Condition.Bool.aws:SecureTransport` | `"false"` | **`"true"` would block HTTPS callers** |

> The most common misconfiguration is setting the condition value to `"true"` instead of `"false"`. That denies HTTPS (secure) callers and breaks everything. Confirm the value is `"false"`.

---

## Phase 2 — Verify Queue Configuration Is Unchanged (5 min)

Click the **"Configuration"** and **"Encryption"** tabs and confirm everything is identical to the no-tls baseline:

| Attribute | Expected (same as no-tls) |
|---|---|
| Visibility timeout | 30 seconds |
| Message retention | 4 days (345,600s) |
| Receive wait time | 20 seconds |
| KMS key | Same customer-managed key ARN |
| DLQ | Configured, maxRetry=3 |

> Adding a queue policy does not touch any of these settings. If something changed, Terraform may have drifted.

---

## Phase 3 — CRITICAL: Send a Message via Console (5 min)

This is the most important test. The console uses HTTPS to call SQS, so the Deny should have no effect.

### Step 3.1 — Open Send and Receive Messages

Click **"Send and receive messages"** (top-right button).

### Step 3.2 — Send a Test Message

In the **"Send message"** panel:

1. **Message body**:
   ```
   {"event":"test","source":"console","phase":"with-tls-policy","timestamp":"2026-02-17"}
   ```
2. Click **"Send message"**

**Expected**: ✅ Green success banner — `"Message sent successfully"`

**If you see**: ❌ `AccessDenied` — STOP. The policy condition value is wrong (likely `"true"` instead of `"false"`). Go back and check the Access policy tab.

---

## Phase 4 — CRITICAL: Receive the Message via Console (5 min)

### Step 4.1 — Poll for Messages

In the **"Receive messages"** panel, click **"Poll for messages"**.

**Expected**: ✅ Your test message appears within 20 seconds.

**If receive fails with AccessDenied**: The deny is blocking `sqs:ReceiveMessage`. The policy condition or action is misconfigured.

### Step 4.2 — Inspect the Message

Click the Message ID and verify:

| Field | Expected |
|---|---|
| Body | Matches what you sent |
| Receive count | 1 |

### Step 4.3 — Delete the Message

1. Select the message checkbox
2. Click **"Delete"**

**Expected**: ✅ Message deleted successfully.

---

## Phase 5 — CloudTrail Verification — Confirm TLS Was Used (10 min)

This is the proof step: CloudTrail records show TLS details for every SQS API call.

### Step 5.1 — Navigate to CloudTrail

AWS Console → **"CloudTrail"** → **"Event history"**

Filter:
- **Attribute**: Event source
- **Value**: `sqs.amazonaws.com`

### Step 5.2 — Find the SendMessage Event

Click your most recent `SendMessage` event and look for the `tlsDetails` block in the raw JSON:

```json
"tlsDetails": {
  "tlsVersion": "TLSv1.2",
  "cipherSuite": "ECDHE-RSA-AES128-GCM-SHA256"
}
```

**What this confirms**: The console call used TLS. The deny condition is `aws:SecureTransport = false`, which evaluates to `false` for this call (because the call IS secure). So the Deny does not fire.

> Mental model: The deny says "block you IF your transport is NOT secure." This call IS secure, so the deny does not apply.

### Step 5.3 — Confirm Zero AccessDenied Events

Filter:
- **Attribute**: Event source → `sqs.amazonaws.com`
- **Attribute**: Error code → `AccessDenied`

**Expected**: Zero results for your queue.

> This is the definitive proof that the policy did not break anything.

### Step 5.4 — CloudTrail CLI Equivalents

```bash
# Find your SendMessage events and confirm TLS
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=sqs.amazonaws.com \
  --max-results 20 \
  --region us-east-2 \
  | jq '.Events[].CloudTrailEvent | fromjson | {EventName, tlsDetails}'

# Check for any AccessDenied — should return empty
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=sqs.amazonaws.com \
  --max-results 50 \
  --region us-east-2 \
  | jq '[.Events[].CloudTrailEvent | fromjson | select(.errorCode == "AccessDenied")]'
```

**Expected AccessDenied output**: `[]`

---

## Phase 6 — Verify the Policy via CLI (3 min)

This gives you a clean, copy-pasteable verification:

```bash
# Get queue URL
QUEUE_URL=$(cd projects/simple-sqs-with-tls && terraform output -raw queue_url)

# Print the queue policy
aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names Policy \
  --region us-east-2 \
  | jq '.Attributes.Policy | fromjson'
```

**Expected output** — confirm:
1. `"Effect": "Deny"` is present
2. `"Action"` contains `"sqs:*"`
3. `"Bool"."aws:SecureTransport"` = `"false"` (not `"true"`)

```bash
# Send a message via CLI (same as SDK — uses HTTPS)
aws sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body '{"cli-test": "with-tls-policy-active"}' \
  --region us-east-2
```

**Expected**: Response with `MessageId`. If you get `AccessDenied`, the policy is misconfigured.

---

## Phase 7 — Understanding What Would Fail (No Console Test Needed)

To understand the boundary — what would actually be blocked — here is the theoretical scenario.

**A call using plain HTTP** (which SQS doesn't even support at the service level):

```
POST http://sqs.us-east-2.amazonaws.com/<account-id>/<queue-name>
Action=SendMessage
MessageBody=test
```

This would return `AccessDenied` because:
1. The service layer would likely reject it anyway (no HTTP endpoint)
2. Even if it somehow reached the policy layer, `aws:SecureTransport = false` would be true, triggering the deny

**Conclusion**: This deny only affects callers that are already broken.

---

## Expected Results Summary

| Test | Expected Result | Fail action |
|---|---|---|
| Access policy tab shows JSON | Yes | Check `aws_sqs_queue_policy` resource in Terraform state |
| Policy Effect = Deny | Yes | Terraform bug — re-apply |
| Policy action = sqs:* | Yes | Terraform bug — re-apply |
| **Policy condition value = "false"** | **Yes** | **CRITICAL: re-apply, condition value "true" breaks everything** |
| Send via console | **SUCCESS** | Policy misconfigured — check condition value |
| Receive via console | **SUCCESS** | Policy misconfigured — check condition value |
| Delete via console | **SUCCESS** | Policy misconfigured — check condition value |
| CloudTrail TLS shown | TLSv1.2 or TLSv1.3 | Investigate — unusual |
| CloudTrail AccessDenied | **Zero results** | **STOP: find the caller and fix before rollout** |

---

## Troubleshooting

### AccessDenied on SendMessage after applying policy

❌ **Error**: `An error occurred (AccessDenied) when calling the SendMessage operation`

✅ **Diagnosis**:

```bash
# Check the exact condition value in the policy
aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names Policy \
  --region us-east-2 \
  | jq '.Attributes.Policy | fromjson | .Statement[].Condition'
```

Look at the output:

```json
{ "Bool": { "aws:SecureTransport": "false" } }   ← CORRECT — denies non-TLS
{ "Bool": { "aws:SecureTransport": "true" } }    ← WRONG — denies TLS callers
```

If the value is `"true"`, destroy and re-apply. The module's `main.tf` hardcodes `"false"` — this should not happen unless the module was modified.

### Policy not showing in Access policy tab

❌ **Issue**: The tab shows empty / default policy

✅ **Fix**:
```bash
# Confirm resource exists in state
terraform state list | grep sqs_queue_policy

# Force re-apply
terraform apply -target=module.sqs
```

### Cannot find queue in console

❌ **Issue**: Queue not visible

✅ **Fix**:
```bash
# List queues
aws sqs list-queues --region us-east-2 | jq '.QueueUrls[]'
```

If queue doesn't exist — Terraform apply failed. Check `terraform show`.

---

## Rollout Decision

After this testing guide is complete, you can make a confident rollout decision:

| Evidence | What it proves |
|---|---|
| Policy is attached and correctly formed | The governance control is active |
| Send/Receive/Delete all succeeded via console | Standard callers (HTTPS) are unaffected |
| CLI operations also succeeded | SDKs (boto3, AWS CLI) are unaffected |
| Zero AccessDenied in CloudTrail | No legitimate callers were broken |
| CloudTrail shows TLSv1.2/1.3 on all events | All existing traffic was already TLS |

**Conclusion**: The SecureTransport deny is safe to add to all queues via Terraform.

---

## Files Reference

| File | Purpose |
|---|---|
| `main.tf` | Infrastructure with `enable_secure_transport = true` |
| `variables.tf` | Input variables |
| `outputs.tf` | Includes `verify_policy` command |
| `tests/test_sqs.py` | Automated integration tests (critical tests 09–11) |
| `tests/TEST-CASES.md` | Test case documentation |
| `CONSOLE-TESTING-GUIDE.md` | This file |

---

**Last Updated**: 2026-02-17
**Status**: Phase 2 — SecureTransport policy active
