#!/usr/bin/env python3
"""
Integration tests for simple-sqs-with-tls project.

Verifies that:
  1. The SecureTransport deny policy IS attached and correctly formed
  2. Normal SDK/CLI callers (HTTPS) are NOT broken by the policy:
       - SendMessage still succeeds
       - ReceiveMessage still succeeds
       - DeleteMessage still succeeds
  3. All baseline infrastructure checks still pass (encryption, DLQ, etc.)

This is the critical proof-point of the whole exercise: adding the
aws:SecureTransport=false deny to the queue policy must be a no-op
for any caller that uses HTTPS (which is every standard AWS SDK).

Prerequisites:
  1. terraform apply in simple-sqs-with-tls/ has completed successfully
  2. Valid AWS credentials with sqs:* and kms:* permissions
  3. pip install boto3

Run:
    cd projects/simple-sqs-with-tls
    python3 tests/test_sqs.py

    # Or override queue URL without terraform:
    QUEUE_URL=https://sqs.us-east-2.amazonaws.com/123456789012/my-queue \\
        python3 tests/test_sqs.py
"""

import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    print("ERROR: boto3 is not installed. Run: pip install boto3")
    sys.exit(1)


###############################################################################
# Terraform output discovery
###############################################################################

PROJECT_DIR = Path(__file__).parent.parent  # simple-sqs-with-tls/


def get_terraform_outputs() -> dict:
    env_queue_url = os.environ.get("QUEUE_URL")
    env_dlq_url   = os.environ.get("DLQ_URL")
    env_region    = os.environ.get("AWS_REGION", "us-east-2")

    if env_queue_url:
        return {
            "queue_url": {"value": env_queue_url},
            "dlq_url":   {"value": env_dlq_url or ""},
            "aws_region": {"value": env_region},
            "secure_transport_policy_enabled": {"value": True},
        }

    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            capture_output=True, text=True,
            cwd=str(PROJECT_DIR),
            timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip())
        return json.loads(result.stdout)
    except FileNotFoundError:
        print("WARNING: terraform binary not found. Set QUEUE_URL env var to skip.")
        sys.exit(1)
    except Exception as exc:
        print(f"ERROR reading terraform outputs: {exc}")
        print("Have you run 'terraform apply' in simple-sqs-with-tls/?")
        sys.exit(1)


###############################################################################
# Test state
###############################################################################

PASS_COUNT = 0
FAIL_COUNT = 0
_sent_receipt_handle: str | None = None
_sent_message_body: str = ""


def run_test(name: str, fn) -> bool:
    global PASS_COUNT, FAIL_COUNT
    print(f"\n{'='*60}")
    print(f"Test: {name}")
    print("="*60)
    try:
        fn()
        print("  PASSED")
        PASS_COUNT += 1
        return True
    except AssertionError as exc:
        print(f"  FAILED — {exc}")
        FAIL_COUNT += 1
        return False
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        msg  = exc.response["Error"]["Message"]
        print(f"  FAILED — AWS {code}: {msg}")
        FAIL_COUNT += 1
        return False
    except Exception as exc:
        print(f"  ERROR — {type(exc).__name__}: {exc}")
        FAIL_COUNT += 1
        return False


###############################################################################
# Tests — infrastructure baseline (same as no-tls)
###############################################################################

def test_01_queue_exists(sqs, queue_url: str):
    """Queue URL is reachable and returns attributes."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["All"],
    )["Attributes"]
    assert attrs, "GetQueueAttributes returned empty response"
    print(f"  QueueArn: {attrs.get('QueueArn', 'n/a')}")


def test_02_encryption_at_rest_enabled(sqs, queue_url: str):
    """Customer-managed KMS key must still be in place."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["KmsMasterKeyId"],
    )["Attributes"]
    kms_key = attrs.get("KmsMasterKeyId", "")
    assert kms_key and kms_key != "alias/aws/sqs", (
        f"Expected a customer-managed KMS key, got: '{kms_key}'"
    )
    print(f"  KmsMasterKeyId: {kms_key}")


def test_03_dlq_configured(sqs, queue_url: str):
    """Redrive policy must still point to the DLQ."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["RedrivePolicy"],
    )["Attributes"]
    raw = attrs.get("RedrivePolicy", "")
    assert raw, "RedrivePolicy missing"
    policy = json.loads(raw)
    assert "deadLetterTargetArn" in policy
    assert int(policy.get("maxReceiveCount", 0)) == 3
    print(f"  DeadLetterTargetArn: {policy['deadLetterTargetArn']}")


###############################################################################
# Tests — SecureTransport policy presence and correctness
###############################################################################

def test_04_secure_transport_policy_is_attached(sqs, queue_url: str):
    """
    A queue policy must be attached when enable_secure_transport=true.
    """
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["Policy"],
    )["Attributes"]
    raw_policy = attrs.get("Policy", "")
    assert raw_policy, (
        "No queue policy is attached. Was terraform apply run with enable_secure_transport=true?"
    )
    policy = json.loads(raw_policy)
    print(f"  Policy has {len(policy.get('Statement', []))} statement(s)")
    return policy


def test_05_policy_has_deny_effect(sqs, queue_url: str):
    """Policy must contain at least one Deny statement."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["Policy"],
    )["Attributes"]
    policy = json.loads(attrs["Policy"])
    deny_stmts = [s for s in policy.get("Statement", []) if s.get("Effect") == "Deny"]
    assert deny_stmts, "No Deny statement found in the queue policy"
    print(f"  Found {len(deny_stmts)} Deny statement(s)")


def test_06_deny_has_secure_transport_condition(sqs, queue_url: str):
    """The Deny statement must condition on aws:SecureTransport=false."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["Policy"],
    )["Attributes"]
    policy = json.loads(attrs["Policy"])

    found = False
    for stmt in policy.get("Statement", []):
        if stmt.get("Effect") != "Deny":
            continue
        for test_name, pairs in stmt.get("Condition", {}).items():
            if test_name.lower() in ("bool", "boolIfExists".lower()):
                for key, value in pairs.items():
                    if key.lower() == "aws:securetransport" and str(value).lower() == "false":
                        found = True
                        print(f"  Condition: {test_name}.aws:SecureTransport = {value}")
                        break

    assert found, (
        "No Deny statement with Condition Bool aws:SecureTransport=false found. "
        "The policy is not correctly enforcing SecureTransport."
    )


def test_07_deny_covers_sqs_wildcard_action(sqs, queue_url: str):
    """The SecureTransport deny must cover sqs:* (or *) to be effective."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["Policy"],
    )["Attributes"]
    policy = json.loads(attrs["Policy"])

    for stmt in policy.get("Statement", []):
        if stmt.get("Effect") != "Deny":
            continue
        action = stmt.get("Action", [])
        if isinstance(action, str):
            action = [action]
        if any(a in ("sqs:*", "*") for a in action):
            print(f"  Deny Action: {action}")
            return

    raise AssertionError(
        "No Deny statement covering sqs:* or * found in the queue policy. "
        "The deny must cover sqs:* to block all SQS operations when not using TLS."
    )


def test_08_deny_applies_to_all_principals(sqs, queue_url: str):
    """The SecureTransport deny must apply to Principal=* (all callers)."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["Policy"],
    )["Attributes"]
    policy = json.loads(attrs["Policy"])

    for stmt in policy.get("Statement", []):
        if stmt.get("Effect") != "Deny":
            continue
        principal = stmt.get("Principal", {})
        if principal == "*":
            print("  Principal: * (string wildcard)")
            return
        if isinstance(principal, dict):
            aws = principal.get("AWS", [])
            if isinstance(aws, str):
                aws = [aws]
            if "*" in aws:
                print("  Principal.AWS: *")
                return

    raise AssertionError(
        "No Deny statement with Principal=* found. "
        "The deny must cover all callers (Principal: *) to be effective."
    )


###############################################################################
# Tests — THE CRITICAL PROOF: policy does NOT break standard callers
###############################################################################

def test_09_send_message_succeeds_despite_policy(sqs, queue_url: str):
    """
    CRITICAL TEST: SendMessage must succeed even with the SecureTransport deny.

    boto3 uses HTTPS by default, so aws:SecureTransport=true for this call.
    The deny fires only when SecureTransport=false — which this call is not.
    If this test fails with AccessDenied, something is very wrong with the policy.
    """
    global _sent_message_body, _sent_receipt_handle
    _sent_message_body = f"test-with-tls-policy-{uuid.uuid4()}"

    try:
        response = sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=_sent_message_body,
        )
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        raise AssertionError(
            f"SendMessage failed with {code} — the SecureTransport policy may be incorrectly "
            "blocking HTTPS callers. Check the deny condition value is 'false' not 'true'."
        ) from exc

    http_code = response["ResponseMetadata"]["HTTPStatusCode"]
    msg_id    = response.get("MessageId", "")

    assert http_code == 200, f"Expected HTTP 200, got {http_code}"
    assert msg_id,           "SendMessage did not return a MessageId"
    print(f"  MessageId: {msg_id}")
    print(f"  Policy did NOT block this HTTPS call — as expected")


def test_10_receive_message_succeeds_despite_policy(sqs, queue_url: str):
    """
    CRITICAL TEST: ReceiveMessage must succeed even with the SecureTransport deny.
    """
    global _sent_receipt_handle

    time.sleep(1)

    try:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=5,
        )
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        raise AssertionError(
            f"ReceiveMessage failed with {code} — the SecureTransport policy may be incorrectly "
            "blocking HTTPS callers."
        ) from exc

    messages = response.get("Messages", [])
    assert messages, "ReceiveMessage returned no messages"
    msg = messages[0]
    assert msg["Body"] == _sent_message_body, (
        f"Body mismatch.\n  Expected: {_sent_message_body}\n  Got: {msg['Body']}"
    )
    _sent_receipt_handle = msg["ReceiptHandle"]
    print(f"  Received MessageId: {msg['MessageId']}")
    print(f"  Body matches — policy did NOT block this HTTPS call")


def test_11_delete_message_succeeds_despite_policy(sqs, queue_url: str):
    """
    CRITICAL TEST: DeleteMessage must succeed even with the SecureTransport deny.
    """
    if not _sent_receipt_handle:
        raise AssertionError("No receipt handle — test_10 did not capture a message")

    try:
        response = sqs.delete_message(
            QueueUrl=queue_url,
            ReceiptHandle=_sent_receipt_handle,
        )
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        raise AssertionError(
            f"DeleteMessage failed with {code} — the SecureTransport policy may be "
            "incorrectly blocking HTTPS callers."
        ) from exc

    http_code = response["ResponseMetadata"]["HTTPStatusCode"]
    assert http_code == 200, f"Expected HTTP 200, got {http_code}"
    print("  Message deleted — policy did NOT block this HTTPS call")


def test_12_dlq_accessible(sqs, dlq_url: str):
    """DLQ must remain accessible (not affected by the main queue policy)."""
    if not dlq_url:
        raise AssertionError("DLQ URL is empty")

    attrs = sqs.get_queue_attributes(
        QueueUrl=dlq_url,
        AttributeNames=["MessageRetentionPeriod", "QueueArn"],
    )["Attributes"]

    retention = int(attrs.get("MessageRetentionPeriod", 0))
    assert retention == 1209600, f"Expected DLQ retention=1209600, got {retention}"
    print(f"  DLQ ARN: {attrs.get('QueueArn')}")
    print(f"  DLQ retention: {retention}s — accessible and unchanged")


###############################################################################
# Main
###############################################################################

def main() -> int:
    global PASS_COUNT, FAIL_COUNT

    print("\n" + "="*60)
    print("simple-sqs-with-tls — Integration Test Suite")
    print("Phase 2: Verify SecureTransport policy does NOT break callers")
    print("="*60)

    outputs    = get_terraform_outputs()
    queue_url  = outputs["queue_url"]["value"]
    dlq_url    = outputs.get("dlq_url", {}).get("value", "")
    aws_region = outputs.get("aws_region", {}).get("value", "us-east-2")

    print(f"\nQueue URL : {queue_url}")
    print(f"DLQ URL   : {dlq_url or '(none)'}")
    print(f"Region    : {aws_region}")

    sqs = boto3.client("sqs", region_name=aws_region)

    tests = [
        # Baseline checks
        ("01 Queue exists and is reachable",                  lambda: test_01_queue_exists(sqs, queue_url)),
        ("02 KMS encryption at rest is still configured",     lambda: test_02_encryption_at_rest_enabled(sqs, queue_url)),
        ("03 DLQ redrive policy still configured",            lambda: test_03_dlq_configured(sqs, queue_url)),
        # Policy presence and correctness
        ("04 SecureTransport queue policy IS attached",       lambda: test_04_secure_transport_policy_is_attached(sqs, queue_url)),
        ("05 Policy contains a Deny statement",               lambda: test_05_policy_has_deny_effect(sqs, queue_url)),
        ("06 Deny conditions on aws:SecureTransport=false",   lambda: test_06_deny_has_secure_transport_condition(sqs, queue_url)),
        ("07 Deny covers sqs:* action",                       lambda: test_07_deny_covers_sqs_wildcard_action(sqs, queue_url)),
        ("08 Deny applies to all principals (*)",             lambda: test_08_deny_applies_to_all_principals(sqs, queue_url)),
        # CRITICAL: policy must not break HTTPS callers
        ("09 [CRITICAL] SendMessage succeeds despite policy", lambda: test_09_send_message_succeeds_despite_policy(sqs, queue_url)),
        ("10 [CRITICAL] ReceiveMessage succeeds despite policy", lambda: test_10_receive_message_succeeds_despite_policy(sqs, queue_url)),
        ("11 [CRITICAL] DeleteMessage succeeds despite policy", lambda: test_11_delete_message_succeeds_despite_policy(sqs, queue_url)),
        ("12 DLQ still accessible",                           lambda: test_12_dlq_accessible(sqs, dlq_url)),
    ]

    for name, fn in tests:
        run_test(name, fn)

    total = PASS_COUNT + FAIL_COUNT
    print("\n" + "="*60)
    print("Integration Test Summary — simple-sqs-with-tls")
    print("="*60)
    print(f"Total: {PASS_COUNT}/{total} passed")

    # Highlight the critical tests
    print("\nCritical tests (09–11): these MUST pass for the policy to be safe to roll out.")

    if FAIL_COUNT == 0:
        print("\nAll tests passed!")
        print("CONCLUSION: The SecureTransport deny policy is correctly formed and")
        print("            does NOT break standard HTTPS callers (SDK, CLI, Terraform).")
        print("            Safe to apply to all 190 queues.")
        return 0
    else:
        print(f"\n{FAIL_COUNT} test(s) failed.")
        print("If tests 09–11 failed with AccessDenied, check the policy condition:")
        print("  - Condition value must be 'false' (deny when NOT using TLS)")
        print("  - NOT 'true' (that would deny HTTPS callers)")
        return 1


if __name__ == "__main__":
    sys.exit(main())
