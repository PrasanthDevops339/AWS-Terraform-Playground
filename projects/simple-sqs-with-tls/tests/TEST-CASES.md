# Test Cases — simple-sqs-with-tls

**Test file**: `test_sqs.py`
**Type**: Integration tests (requires `terraform apply` + AWS credentials)
**Phase**: 2 of 2 — prove the SecureTransport deny policy does NOT break standard callers

> Run `simple-sqs-no-tls` tests first and confirm all 10 pass before running these.

---

## How to Run

```bash
# Install dependency
pip install -r tests/requirements.txt

# Run tests (reads terraform outputs automatically)
cd projects/simple-sqs-with-tls
python3 tests/test_sqs.py

# Override queue URL without terraform
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

**What it does**: Same as no-tls TC-01. Confirms the queue is reachable before running policy-specific tests.

**Pass condition**: `GetQueueAttributes` returns a non-empty dict.

---

### TC-02 — KMS encryption at rest is still configured

| | |
|---|---|
| **ID** | TC-02 |
| **Name** | KMS encryption at rest is still configured |
| **Function** | `test_02_encryption_at_rest_enabled` |
| **Type** | Configuration / Regression |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Confirms the `KmsMasterKeyId` is still a customer-managed key. Adding a queue policy must not affect encryption settings.

**Pass condition**: `KmsMasterKeyId` is non-empty and is not `alias/aws/sqs`.

**Why run it again**: Regression guard. Ensures the policy addition (`aws_sqs_queue_policy` resource) didn't accidentally reset queue attributes.

---

### TC-03 — DLQ redrive policy is still configured

| | |
|---|---|
| **ID** | TC-03 |
| **Name** | DLQ redrive policy is still configured |
| **Function** | `test_03_dlq_configured` |
| **Type** | Configuration / Regression |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Confirms `RedrivePolicy` still has `deadLetterTargetArn` and `maxReceiveCount=3`. Adding a queue policy must not reset the redrive policy.

**Pass condition**: Both fields present and correct.

---

### TC-04 — SecureTransport queue policy IS attached

| | |
|---|---|
| **ID** | TC-04 |
| **Name** | SecureTransport queue policy is attached |
| **Function** | `test_04_secure_transport_policy_is_attached` |
| **Type** | Security / State |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Reads the `Policy` attribute. Asserts it is non-empty (a policy document exists).

**Pass condition**: `Policy` attribute is a non-empty JSON string.

**Fail means**: `aws_sqs_queue_policy` resource was not created (Terraform apply failed or `enable_secure_transport = false`). Check `terraform output secure_transport_policy_enabled` — should be `true`.

---

### TC-05 — Policy contains a Deny statement

| | |
|---|---|
| **ID** | TC-05 |
| **Name** | Policy contains a Deny statement |
| **Function** | `test_05_policy_has_deny_effect` |
| **Type** | Security / Policy Structure |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Parses the queue policy and counts statements with `"Effect": "Deny"`. Asserts at least one exists.

**Pass condition**: At least one Deny statement found.

**Fail means**: Policy document is malformed, or only Allow statements were generated.

---

### TC-06 — Deny conditions on aws:SecureTransport = false

| | |
|---|---|
| **ID** | TC-06 |
| **Name** | Deny conditions on aws:SecureTransport = false |
| **Function** | `test_06_deny_has_secure_transport_condition` |
| **Type** | Security / Policy Correctness |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Scans all Deny statements for a `Condition` block where:
- Condition test is `Bool` or `BoolIfExists`
- Key is `aws:SecureTransport`
- Value is `"false"` (string, case-insensitive)

**Pass condition**: At least one such Deny statement is found.

**Fail means**: The condition value is wrong (most commonly `"true"` instead of `"false"`).

> **Critical distinction**:
> - `aws:SecureTransport = "false"` → Deny fires when transport is NOT secure. Correct.
> - `aws:SecureTransport = "true"` → Deny fires when transport IS secure. Breaks all HTTPS callers.

**If this fails**: Immediately check the condition value in the Access policy tab. Do not proceed to TC-09–11.

---

### TC-07 — Deny covers sqs:* action

| | |
|---|---|
| **ID** | TC-07 |
| **Name** | Deny covers sqs:* action |
| **Function** | `test_07_deny_covers_sqs_wildcard_action` |
| **Type** | Security / Policy Completeness |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Checks that the SecureTransport Deny statement's `Action` contains either `sqs:*` or `*`.

**Pass condition**: At least one Deny statement has `sqs:*` or `*` in its Action list.

**Fail means**: The deny is scoped too narrowly (e.g., only `sqs:SendMessage`) and would leave other operations unprotected.

**Why sqs:* matters**: The deny must cover all SQS operations — SendMessage, ReceiveMessage, DeleteMessage, GetQueueAttributes, etc. Scoping to specific actions creates gaps.

---

### TC-08 — Deny applies to all principals (*)

| | |
|---|---|
| **ID** | TC-08 |
| **Name** | Deny applies to all principals |
| **Function** | `test_08_deny_applies_to_all_principals` |
| **Type** | Security / Policy Completeness |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Checks that the SecureTransport Deny statement's `Principal` is a wildcard:
- `"Principal": "*"` (string)
- `"Principal": { "AWS": "*" }` (dict)

**Pass condition**: At least one Deny with SecureTransport condition has a wildcard principal.

**Fail means**: The deny only covers specific IAM roles/users, leaving other callers unprotected.

---

### TC-09 — [CRITICAL] SendMessage succeeds despite policy

| | |
|---|---|
| **ID** | TC-09 |
| **Name** | SendMessage succeeds despite SecureTransport policy |
| **Function** | `test_09_send_message_succeeds_despite_policy` |
| **Type** | CRITICAL — Functional / Non-regression |
| **AWS API** | `sqs:SendMessage` |

**What it does**: Sends a message with a unique UUID body using `boto3.send_message`. boto3 uses HTTPS internally (the AWS SDK always uses HTTPS/TLS by default). Asserts HTTP `200` and a non-empty `MessageId`.

**The logic**:

```
Policy says: Deny sqs:* IF aws:SecureTransport = "false"
boto3 call:  aws:SecureTransport = true  (it uses HTTPS)
Therefore:   Deny condition evaluates to FALSE → Deny does NOT fire
Result:      Message sends successfully
```

**Pass condition**: `SendMessage` returns HTTP 200 with a MessageId.

**Fail condition**: `AccessDenied` — this means the policy is misconfigured (likely `SecureTransport = "true"` instead of `"false"`).

**Side effect**: Stores message body and receipt handle for TC-10 and TC-11.

**This is one of the three must-pass tests for rollout approval.**

---

### TC-10 — [CRITICAL] ReceiveMessage succeeds despite policy

| | |
|---|---|
| **ID** | TC-10 |
| **Name** | ReceiveMessage succeeds despite SecureTransport policy |
| **Function** | `test_10_receive_message_succeeds_despite_policy` |
| **Type** | CRITICAL — Functional / Non-regression |
| **AWS API** | `sqs:ReceiveMessage` |

**What it does**: Polls for messages using `boto3.receive_message`. Asserts:
- Call does not raise `AccessDenied`
- At least one message is returned
- Message body matches the UUID sent in TC-09

**The logic**: Same as TC-09 — boto3 uses HTTPS, so `aws:SecureTransport = true`, so the Deny does not fire.

**Pass condition**: Message received with matching body.

**Fail with AccessDenied**: Policy misconfiguration — check condition value immediately.

**Side effect**: Stores `ReceiptHandle` for TC-11.

**This is one of the three must-pass tests for rollout approval.**

---

### TC-11 — [CRITICAL] DeleteMessage succeeds despite policy

| | |
|---|---|
| **ID** | TC-11 |
| **Name** | DeleteMessage succeeds despite SecureTransport policy |
| **Function** | `test_11_delete_message_succeeds_despite_policy` |
| **Type** | CRITICAL — Functional / Non-regression |
| **AWS API** | `sqs:DeleteMessage` |

**What it does**: Deletes the message received in TC-10 using its `ReceiptHandle`. Asserts HTTP `200`.

**The logic**: Same HTTPS reasoning as TC-09 and TC-10.

**Pass condition**: Delete returns HTTP 200.

**Fail with AccessDenied**: Policy misconfiguration.

**This is one of the three must-pass tests for rollout approval.**

---

### TC-12 — DLQ still accessible

| | |
|---|---|
| **ID** | TC-12 |
| **Name** | DLQ still accessible and unchanged |
| **Function** | `test_12_dlq_accessible` |
| **Type** | Configuration / Regression |
| **AWS API** | `sqs:GetQueueAttributes` |

**What it does**: Confirms the DLQ (`-dlq` queue) is still accessible and retains the 14-day message retention. The queue policy on the main queue does not affect the DLQ (it is a separate resource).

**Pass condition**: `MessageRetentionPeriod == 1209600` on the DLQ.

---

## Test Execution Order

TC-09, TC-10, and TC-11 form a dependent pipeline:

```
TC-01  (smoke)
TC-02  (regression — encryption unchanged)
TC-03  (regression — DLQ unchanged)
TC-04  (policy present)
TC-05  (policy has deny)
TC-06  (deny has correct condition)
TC-07  (deny has correct action)
TC-08  (deny has correct principal)
TC-09 → TC-10 → TC-11  [CRITICAL pipeline — order matters]
TC-12  (regression — DLQ accessible)
```

---

## Critical Tests (TC-09, TC-10, TC-11)

These three tests are the **go/no-go gate** for the rollout decision.

| Result | Meaning | Action |
|---|---|---|
| All three pass | Policy is correct — HTTPS callers unaffected | Safe to roll out to all queues |
| Any fails with `AccessDenied` | Policy condition value is wrong | Fix immediately — do NOT roll out |
| Any fails with other error | Infrastructure or IAM issue | Investigate before rolling out |

If TC-09–11 fail with `AccessDenied`, run this to diagnose:

```bash
aws sqs get-queue-attributes \
  --queue-url "$(cd .. && terraform output -raw queue_url)" \
  --attribute-names Policy \
  --region us-east-2 \
  | jq '.Attributes.Policy | fromjson | .Statement[].Condition'
```

The condition value **must be** `"false"`, not `"true"`.

---

## Pass / Fail Criteria

The test suite exits `0` only when all 12 tests pass.

| Outcome | Exit code | Rollout decision |
|---|---|---|
| All 12 passed | `0` | **APPROVED** — safe to add policy to all queues |
| TC-09/10/11 failed with AccessDenied | `1` | **BLOCKED** — fix policy condition value |
| TC-04–08 failed | `1` | **BLOCKED** — policy not correctly attached |
| TC-01–03, TC-12 failed | `1` | **INVESTIGATE** — infrastructure issue |

---

## Relationship to Console Testing

| Console step (CONSOLE-TESTING-GUIDE.md) | Automated test |
|---|---|
| Queue visible | TC-01 |
| Encryption tab unchanged | TC-02 |
| DLQ tab unchanged | TC-03 |
| Access policy tab shows JSON | TC-04 |
| Policy has Deny | TC-05 |
| Deny has aws:SecureTransport=false | TC-06 |
| Action covers sqs:* | TC-07 |
| Principal is * | TC-08 |
| Send via console succeeds | TC-09 |
| Receive via console succeeds | TC-10 |
| Delete via console succeeds | TC-11 |
| DLQ accessible | TC-12 |
| CloudTrail shows TLS | Not automated — manual CloudTrail check required |
| CloudTrail shows zero AccessDenied | Not automated — manual CloudTrail check required |

> CloudTrail checks require human judgement (looking across all callers) and are documented in `CONSOLE-TESTING-GUIDE.md`.

---

## Unit Test Coverage

The policy document structure is independently validated by the unit tests in `Terrafrom-AWS-Prasanth/terraform-aws-sqs/tests/test_policy_unit.py`, which run without AWS credentials and cover:

- All fields in the module's generated policy (Effect, Principal, Action, Condition)
- Non-compliant shapes (wrong action, wrong condition key, wrong value, wrong principal)
- Alternative valid shapes (Action=*, BoolIfExists, Principal string)

Run before deploying to catch policy logic issues early:

```bash
python3 ../../Terrafrom-AWS-Prasanth/terraform-aws-sqs/tests/test_policy_unit.py
```

---

**Last Updated**: 2026-02-17
**Status**: Phase 2 — SecureTransport policy active
