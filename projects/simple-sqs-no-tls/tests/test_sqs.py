#!/usr/bin/env python3
"""
Integration tests for simple-sqs-no-tls project.

Verifies the baseline SQS deployment:
  - Queue and DLQ exist and are reachable
  - Encryption at rest (KMS) is configured
  - Long polling is configured
  - Redrive / DLQ policy is set
  - NO SecureTransport deny policy is attached
  - Send / Receive / Delete message all succeed

Prerequisites:
  1. terraform apply in simple-sqs-no-tls/ has completed successfully
  2. Valid AWS credentials with sqs:* and kms:* permissions
  3. pip install boto3

Run:
    cd projects/simple-sqs-no-tls
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

PROJECT_DIR = Path(__file__).parent.parent  # simple-sqs-no-tls/


def get_terraform_outputs() -> dict:
    """
    Read Terraform outputs from the project directory.
    Falls back to environment variables if terraform is not initialised.
    """
    # Allow overrides via env vars for CI / manual runs
    env_queue_url = os.environ.get("QUEUE_URL")
    env_dlq_url   = os.environ.get("DLQ_URL")
    env_region    = os.environ.get("AWS_REGION", "us-east-2")

    if env_queue_url:
        return {
            "queue_url": {"value": env_queue_url},
            "dlq_url":   {"value": env_dlq_url or ""},
            "aws_region": {"value": env_region},
            "secure_transport_policy_enabled": {"value": False},
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
        print("Have you run 'terraform apply' in simple-sqs-no-tls/?")
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
# Tests
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
    """Queue must have a customer-managed KMS key configured (not SSE-SQS)."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["KmsMasterKeyId", "KmsDataKeyReusePeriodSeconds"],
    )["Attributes"]

    kms_key = attrs.get("KmsMasterKeyId", "")
    assert kms_key, (
        "KmsMasterKeyId is empty — KMS at-rest encryption is not configured"
    )
    assert kms_key != "alias/aws/sqs", (
        f"KmsMasterKeyId is the AWS-managed default key '{kms_key}'. "
        "A customer-managed key is expected."
    )
    print(f"  KmsMasterKeyId: {kms_key}")
    print(f"  KmsDataKeyReusePeriodSeconds: {attrs.get('KmsDataKeyReusePeriodSeconds')}")


def test_03_long_polling_configured(sqs, queue_url: str):
    """ReceiveMessageWaitTimeSeconds must be 20 (long polling)."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["ReceiveMessageWaitTimeSeconds"],
    )["Attributes"]
    wait = int(attrs.get("ReceiveMessageWaitTimeSeconds", 0))
    assert wait == 20, (
        f"Expected ReceiveMessageWaitTimeSeconds=20 (long polling), got {wait}"
    )
    print(f"  ReceiveMessageWaitTimeSeconds: {wait}")


def test_04_message_retention_period(sqs, queue_url: str):
    """MessageRetentionPeriod must be 345600 seconds (4 days)."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["MessageRetentionPeriod"],
    )["Attributes"]
    retention = int(attrs.get("MessageRetentionPeriod", 0))
    assert retention == 345600, (
        f"Expected MessageRetentionPeriod=345600, got {retention}"
    )
    print(f"  MessageRetentionPeriod: {retention}s ({retention // 86400} days)")


def test_05_dlq_configured(sqs, queue_url: str):
    """RedrivePolicy must point to the DLQ with maxReceiveCount=3."""
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["RedrivePolicy"],
    )["Attributes"]
    raw = attrs.get("RedrivePolicy", "")
    assert raw, "RedrivePolicy attribute is missing — DLQ redrive is not configured"

    policy = json.loads(raw)
    assert "deadLetterTargetArn" in policy, "RedrivePolicy missing deadLetterTargetArn"
    assert int(policy.get("maxReceiveCount", 0)) == 3, (
        f"Expected maxReceiveCount=3, got {policy.get('maxReceiveCount')}"
    )
    print(f"  DeadLetterTargetArn: {policy['deadLetterTargetArn']}")
    print(f"  MaxReceiveCount: {policy['maxReceiveCount']}")


def test_06_no_secure_transport_deny_policy(sqs, queue_url: str):
    """
    No queue policy should be attached, OR if one exists it must NOT contain
    an aws:SecureTransport deny (that is the with-tls project's job).
    """
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["Policy"],
    )["Attributes"]

    raw_policy = attrs.get("Policy", "")
    if not raw_policy:
        print("  No queue policy attached — as expected for no-tls baseline")
        return

    policy = json.loads(raw_policy)
    for stmt in policy.get("Statement", []):
        if stmt.get("Effect") != "Deny":
            continue
        condition = stmt.get("Condition", {})
        for pairs in condition.values():
            for key, value in pairs.items():
                if key.lower() == "aws:securetransport" and str(value).lower() == "false":
                    raise AssertionError(
                        "Found a SecureTransport deny in the queue policy. "
                        "This is the simple-sqs-no-tls project — no deny expected."
                    )
    print("  Policy present but contains no SecureTransport deny — OK")


def test_07_send_message(sqs, queue_url: str):
    """SendMessage must return HTTP 200 and a MessageId."""
    global _sent_message_body, _sent_receipt_handle
    _sent_message_body = f"test-message-{uuid.uuid4()}"

    response = sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=_sent_message_body,
    )
    http_code = response["ResponseMetadata"]["HTTPStatusCode"]
    msg_id    = response.get("MessageId", "")

    assert http_code == 200, f"Expected HTTP 200, got {http_code}"
    assert msg_id,           "SendMessage did not return a MessageId"
    print(f"  MessageId: {msg_id}")
    print(f"  MessageBody: {_sent_message_body}")


def test_08_receive_message(sqs, queue_url: str):
    """ReceiveMessage must return the message we just sent."""
    global _sent_receipt_handle

    # Allow a brief propagation delay
    time.sleep(1)

    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=5,
    )
    messages = response.get("Messages", [])
    assert messages, "ReceiveMessage returned no messages — message may not have propagated yet"

    msg = messages[0]
    assert msg["Body"] == _sent_message_body, (
        f"Message body mismatch.\n  Expected: {_sent_message_body}\n  Got: {msg['Body']}"
    )
    _sent_receipt_handle = msg["ReceiptHandle"]
    print(f"  Received MessageId: {msg['MessageId']}")
    print(f"  Body matches — OK")


def test_09_delete_message(sqs, queue_url: str):
    """DeleteMessage must clean up the received message."""
    if not _sent_receipt_handle:
        raise AssertionError("No receipt handle — test_08 did not capture a message")

    response = sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=_sent_receipt_handle,
    )
    http_code = response["ResponseMetadata"]["HTTPStatusCode"]
    assert http_code == 200, f"Expected HTTP 200 on delete, got {http_code}"
    print("  Message deleted — queue clean")


def test_10_dlq_accessible(sqs, dlq_url: str):
    """DLQ must also be reachable and have the expected retention period."""
    if not dlq_url:
        raise AssertionError("DLQ URL is empty — was it created?")

    attrs = sqs.get_queue_attributes(
        QueueUrl=dlq_url,
        AttributeNames=["MessageRetentionPeriod", "QueueArn"],
    )["Attributes"]

    retention = int(attrs.get("MessageRetentionPeriod", 0))
    assert retention == 1209600, (
        f"Expected DLQ retention=1209600 (14 days), got {retention}"
    )
    print(f"  DLQ ARN: {attrs.get('QueueArn')}")
    print(f"  DLQ retention: {retention}s ({retention // 86400} days)")


###############################################################################
# Main
###############################################################################

def main() -> int:
    global PASS_COUNT, FAIL_COUNT

    print("\n" + "="*60)
    print("simple-sqs-no-tls — Integration Test Suite")
    print("Phase 1: Baseline (no SecureTransport policy)")
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
        ("01 Queue exists and is reachable",              lambda: test_01_queue_exists(sqs, queue_url)),
        ("02 KMS encryption at rest is configured",       lambda: test_02_encryption_at_rest_enabled(sqs, queue_url)),
        ("03 Long polling configured (wait=20s)",         lambda: test_03_long_polling_configured(sqs, queue_url)),
        ("04 Message retention is 4 days (345600s)",      lambda: test_04_message_retention_period(sqs, queue_url)),
        ("05 DLQ redrive policy configured (maxRetry=3)", lambda: test_05_dlq_configured(sqs, queue_url)),
        ("06 No SecureTransport deny policy attached",    lambda: test_06_no_secure_transport_deny_policy(sqs, queue_url)),
        ("07 SendMessage succeeds",                       lambda: test_07_send_message(sqs, queue_url)),
        ("08 ReceiveMessage returns the sent message",    lambda: test_08_receive_message(sqs, queue_url)),
        ("09 DeleteMessage cleans up the message",        lambda: test_09_delete_message(sqs, queue_url)),
        ("10 DLQ is accessible and has 14-day retention", lambda: test_10_dlq_accessible(sqs, dlq_url)),
    ]

    for name, fn in tests:
        run_test(name, fn)

    total = PASS_COUNT + FAIL_COUNT
    print("\n" + "="*60)
    print("Integration Test Summary — simple-sqs-no-tls")
    print("="*60)
    print(f"Total: {PASS_COUNT}/{total} passed")

    if FAIL_COUNT == 0:
        print("\nAll baseline tests passed!")
        print("Next step: run simple-sqs-with-tls to verify the policy is a no-op.")
        return 0
    else:
        print(f"\n{FAIL_COUNT} test(s) failed — fix before proceeding to with-tls.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
