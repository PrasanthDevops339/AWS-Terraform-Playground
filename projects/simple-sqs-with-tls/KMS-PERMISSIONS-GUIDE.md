# KMS Permissions and Secure Transport — How They Work Together

**Project**: `simple-sqs-with-tls`
**Related files**: `main.tf`, `tests/test_kms.py`

---

## Overview: Two Independent Security Planes

When `enable_secure_transport = true` is set on an SQS queue, two separate
security controls are active simultaneously. They serve different purposes and
do not depend on each other.

| Control | What it protects | Where it lives |
|---|---|---|
| `aws:SecureTransport` deny | Transport layer — ensures callers use HTTPS | SQS queue policy |
| KMS encryption (SSE-KMS) | Data at rest — messages stored on disk are encrypted | KMS key policy + IAM |

Adding the SecureTransport deny does **not** change what KMS permissions are
needed, and KMS permissions have no effect on whether the transport deny fires.
They are independent axes of control.

---

## How SQS + KMS Encryption Works (The Call Flow)

Every `SendMessage` and `ReceiveMessage` involves two separate AWS API calls:

```
┌─────────────────────────────────────────────────────────────────┐
│                        SEND MESSAGE                             │
│                                                                 │
│  Producer role                                                  │
│       │                                                         │
│       ▼                                                         │
│  sqs:SendMessage  ──── SQS Queue Policy checks:                │
│       │                  ✓ aws:SecureTransport=true (HTTPS)     │
│       │                  → deny does NOT fire                   │
│       │                                                         │
│       ▼                                                         │
│  SQS calls KMS ──── KMS Key Policy checks:                     │
│  kms:GenerateDataKey   ✓ principal: sqs.amazonaws.com          │
│       │                ✓ condition: kms:CallerAccount matches   │
│       │                → data key is returned                   │
│       │                                                         │
│       ▼                                                         │
│  Message encrypted with data key, stored in SQS               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      RECEIVE MESSAGE                            │
│                                                                 │
│  Consumer role                                                  │
│       │                                                         │
│       ▼                                                         │
│  sqs:ReceiveMessage ── SQS Queue Policy checks:                │
│       │                  ✓ aws:SecureTransport=true (HTTPS)     │
│       │                                                         │
│       ▼                                                         │
│  SQS calls KMS ──── KMS Key Policy checks:                     │
│  kms:Decrypt           ✓ principal: sqs.amazonaws.com          │
│       │                ✓ condition: kms:CallerAccount matches   │
│       │                → plaintext data key is returned         │
│       │                                                         │
│       ▼                                                         │
│  Message decrypted, returned to consumer                       │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight**: SQS makes the KMS calls using `sqs.amazonaws.com` as the
calling service — not the producer or consumer's IAM identity. This is why the
KMS key policy needs `sqs.amazonaws.com` as a principal, not the role ARNs.

---

## Current KMS Key Policy — Statement by Statement

The KMS key in this project has two statements (from [main.tf](main.tf)):

### Statement 1 — `EnableIAMUserPermissions` (added automatically by the KMS module)

```json
{
  "Sid": "EnableIAMUserPermissions",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::<account-id>:root"
  },
  "Action": "kms:*",
  "Resource": "*"
}
```

**What it does**: Grants the root account full control over the key. This
activates **IAM policy delegation** — any IAM role or user in the account can
be granted KMS permissions via their own IAM policies without needing to be
listed in the KMS key policy itself.

**Why it matters for producers/consumers**: Because root has `kms:*` in the
key policy, a producer role with `kms:GenerateDataKey` in its IAM policy can
use the key. The key policy does not need to be updated for each new role.

### Statement 2 — `SQSServicePermissions` (added in `main.tf`)

```json
{
  "Sid": "SQSServicePermissions",
  "Effect": "Allow",
  "Principal": {
    "Service": "sqs.amazonaws.com"
  },
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:DescribeKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:CallerAccount": "<account-id>"
    }
  }
}
```

**What it does**: Grants the SQS service the KMS operations it needs to
encrypt outgoing messages and decrypt incoming messages. The `kms:CallerAccount`
condition prevents other accounts' SQS queues from using this key.

---

## What Producer and Consumer Roles Need

Even though SQS is the one calling KMS, the **caller's IAM identity is also
evaluated by KMS** as part of the authorization check. This means the role
calling `sqs:SendMessage` or `sqs:ReceiveMessage` must also have the
corresponding KMS permissions granted via IAM policy.

### Producer (publishes messages to SQS)

| KMS Action | Why needed |
|---|---|
| `kms:GenerateDataKey` | SQS calls this to get a data key for encrypting the message |
| `kms:DescribeKey` | SQS validates the key before using it |

Minimum IAM policy for a producer role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSQSPublish",
      "Effect": "Allow",
      "Action": ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"],
      "Resource": "<queue-arn>"
    },
    {
      "Sid": "AllowKMSForSQSPublish",
      "Effect": "Allow",
      "Action": ["kms:GenerateDataKey", "kms:DescribeKey"],
      "Resource": "<kms-key-arn>"
    }
  ]
}
```

### Consumer (receives messages from SQS)

| KMS Action | Why needed |
|---|---|
| `kms:Decrypt` | SQS calls this to decrypt the data key before returning the message |
| `kms:DescribeKey` | SQS validates the key before using it |

Minimum IAM policy for a consumer role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSQSConsume",
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "<queue-arn>"
    },
    {
      "Sid": "AllowKMSForSQSConsume",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:DescribeKey"],
      "Resource": "<kms-key-arn>"
    }
  ]
}
```

### Role that both publishes and consumes

```json
{
  "Sid": "AllowKMSForSQS",
  "Effect": "Allow",
  "Action": ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"],
  "Resource": "<kms-key-arn>"
}
```

---

## Granting Access: Two Approaches

### Option A — IAM Policy Delegation (current demo approach)

Because `EnableIAMUserPermissions` grants `kms:*` to the root account, KMS
permissions can be entirely managed through IAM policies. The KMS key policy
does not need to change when new roles are added.

```
Root is in KMS key policy ──► IAM policies control access to the key
                               No KMS key policy update needed per role
```

**Works well when**: You have centralized IAM governance and trust IAM policies
to be set correctly on each role.

**Risk**: If a role's IAM policy is misconfigured (missing `kms:Decrypt`), the
error will only surface at runtime. The KMS key policy is not the source of
truth for who can use the key.

### Option B — Explicit Role Grants in KMS Key Policy (production hardening)

Add the actual producer/consumer role ARNs directly to the KMS key policy. The
key policy becomes the authoritative access list.

Add to `key_statements` in [main.tf](main.tf):

```hcl
module "kms" {
  source = "../../Terrafrom-AWS-Prasanth/terraform-aws-kms"
  ...
  key_statements = [
    # Existing — keep this
    {
      sid    = "SQSServicePermissions"
      effect = "Allow"
      principals = [{ type = "Service", identifiers = ["sqs.amazonaws.com"] }]
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
      resources  = ["*"]
      conditions = [{
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }]
    },

    # New — producer role (e.g. Lambda that sends order events)
    {
      sid    = "ProducerRolePermissions"
      effect = "Allow"
      principals = [{
        type        = "AWS"
        identifiers = ["arn:aws:iam::<account-id>:role/orders-producer-role"]
      }]
      actions    = ["kms:GenerateDataKey", "kms:DescribeKey"]
      resources  = ["*"]
      conditions = []
    },

    # New — consumer role (e.g. Lambda that processes orders)
    {
      sid    = "ConsumerRolePermissions"
      effect = "Allow"
      principals = [{
        type        = "AWS"
        identifiers = ["arn:aws:iam::<account-id>:role/orders-consumer-role"]
      }]
      actions    = ["kms:Decrypt", "kms:DescribeKey"]
      resources  = ["*"]
      conditions = []
    }
  ]
}
```

**Works well when**: You want the KMS key policy to be the single source of
truth for who can use the key, independent of IAM policies.

---

## Does SecureTransport Affect KMS Requirements?

**No.** The two controls are evaluated independently:

```
SQS queue policy (SecureTransport deny):
  → Evaluated when: any SQS API call is made
  → Checks: was the connection over HTTPS?
  → Has no awareness of KMS

KMS key policy:
  → Evaluated when: SQS calls kms:GenerateDataKey or kms:Decrypt
  → Checks: is the caller an allowed principal with correct conditions?
  → Has no awareness of SQS transport security
```

Setting `enable_secure_transport = true` does not trigger any additional KMS
permission requirements. The KMS setup is identical between `simple-sqs-no-tls`
and `simple-sqs-with-tls`.

---

## Verification Checklist

After deploying, confirm the KMS setup is correct:

```bash
KMS_KEY_ARN=$(terraform output -raw kms_key_arn)
REGION=us-east-2

# 1. Key is in Enabled state with rotation active
aws kms describe-key --key-id "$KMS_KEY_ARN" --region "$REGION" \
  | jq '{KeyState, KeyRotationEnabled: .KeyMetadata.KeyRotationStatus}'

# 2. Get the full key policy and inspect it
aws kms get-key-policy \
  --key-id "$KMS_KEY_ARN" \
  --policy-name default \
  --region "$REGION" \
  | jq '.Policy | fromjson | .Statement[] | {Sid, Effect, Principal}'

# 3. Confirm SQSServicePermissions statement exists
aws kms get-key-policy \
  --key-id "$KMS_KEY_ARN" \
  --policy-name default \
  --region "$REGION" \
  | jq '.Policy | fromjson | .Statement[] | select(.Sid == "SQSServicePermissions")'

# 4. Run the automated KMS tests
python3 tests/test_kms.py
```

---

## Automated Tests

The automated KMS tests live in [tests/test_kms.py](tests/test_kms.py).

| Test | What it verifies |
|---|---|
| KMS-01 | Key exists and is in `Enabled` state |
| KMS-02 | Automatic key rotation is enabled |
| KMS-03 | Key policy is readable and parseable |
| KMS-04 | `EnableIAMUserPermissions` — root account has `kms:*` |
| KMS-05 | `SQSServicePermissions` — SQS service is a principal |
| KMS-06 | SQS service has `kms:GenerateDataKey*` permission |
| KMS-07 | SQS service has `kms:Decrypt` permission |
| KMS-08 | `SQSServicePermissions` has `kms:CallerAccount` condition |
| KMS-09 | Encryption works end-to-end (send + receive proves KMS is functional) |

Run:

```bash
cd projects/simple-sqs-with-tls
python3 tests/test_kms.py
```

---

## Quick Reference: Action Mapping

| SQS operation | KMS call made by SQS | Required on producer/consumer IAM |
|---|---|---|
| `sqs:SendMessage` | `kms:GenerateDataKey` | `kms:GenerateDataKey` |
| `sqs:ReceiveMessage` | `kms:Decrypt` | `kms:Decrypt` |
| `sqs:SendMessageBatch` | `kms:GenerateDataKey` | `kms:GenerateDataKey` |
| Any operation | `kms:DescribeKey` | `kms:DescribeKey` |

---

**Last Updated**: 2026-02-18
**Relates to**: `main.tf`, `tests/test_kms.py`, `CONSOLE-TESTING-GUIDE.md`
