#!/usr/bin/env python3
"""
KMS permission tests for simple-sqs-with-tls project.

Verifies that the KMS key policy is correctly configured to allow SQS to
encrypt and decrypt messages on behalf of callers:

  KMS-01  Key exists and is in Enabled state
  KMS-02  Automatic key rotation is enabled
  KMS-03  Key policy is readable and parseable
  KMS-04  EnableIAMUserPermissions — root account has kms:*
  KMS-05  SQSServicePermissions — sqs.amazonaws.com is a principal
  KMS-06  SQS service has kms:GenerateDataKey* (needed for SendMessage)
  KMS-07  SQS service has kms:Decrypt (needed for ReceiveMessage)
  KMS-08  SQSServicePermissions has kms:CallerAccount condition
  KMS-09  Encryption works end-to-end (send + receive proves KMS is functional)

See KMS-PERMISSIONS-GUIDE.md for a full explanation of the permissions model.

Prerequisites:
  1. terraform apply in simple-sqs-with-tls/ has completed successfully
  2. Valid AWS credentials with:
       kms:DescribeKey, kms:GetKeyPolicy,
       sqs:SendMessage, sqs:ReceiveMessage, sqs:DeleteMessage
  3. pip install boto3

Run:
    cd projects/simple-sqs-with-tls
    python3 tests/test_kms.py

    # Or override without terraform:
    KMS_KEY_ARN=arn:aws:kms:us-east-2:<account>:key/<id> \\
    QUEUE_URL=https://sqs.us-east-2.amazonaws.com/<account>/<queue> \\
    AWS_REGION=us-east-2 \\
    python3 tests/test_kms.py
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
    """Read terraform outputs, or fall back to environment variable overrides."""
    env_key_arn   = os.environ.get("KMS_KEY_ARN")
    env_queue_url = os.environ.get("QUEUE_URL")
    env_region    = os.environ.get("AWS_REGION", "us-east-2")

    if env_key_arn and env_queue_url:
        return {
            "kms_key_arn": {"value": env_key_arn},
            "queue_url":   {"value": env_queue_url},
            "aws_region":  {"value": env_region},
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
        outputs = json.loads(result.stdout)
        # Inject region default if not present as an output
        if "aws_region" not in outputs:
            outputs["aws_region"] = {"value": env_region}
        return outputs
    except FileNotFoundError:
        print("WARNING: terraform binary not found. Set KMS_KEY_ARN + QUEUE_URL env vars to skip.")
        sys.exit(1)
    except Exception as exc:
        print(f"ERROR reading terraform outputs: {exc}")
        print("Have you run 'terraform apply' in simple-sqs-with-tls/?")
        sys.exit(1)


###############################################################################
# Test runner
###############################################################################

PASS_COUNT = 0
FAIL_COUNT = 0

# State shared across TC-09 send → receive
_e2e_message_body: str = ""
_e2e_receipt_handle: str = ""


def run_test(name: str, fn) -> bool:
    global PASS_COUNT, FAIL_COUNT
    print(f"\n{'='*60}")
    print(f"Test: {name}")
    print("=" * 60)
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
# KMS-01 — Key exists and is Enabled
###############################################################################

def test_kms01_key_enabled(kms, key_arn: str):
    """Key must be in Enabled state before any other checks make sense."""
    meta = kms.describe_key(KeyId=key_arn)["KeyMetadata"]
    state = meta["KeyState"]
    assert state == "Enabled", f"Expected KeyState=Enabled, got {state}"
    print(f"  KeyId    : {meta['KeyId']}")
    print(f"  KeyState : {state}")
    print(f"  KeySpec  : {meta.get('KeySpec', 'n/a')}")


###############################################################################
# KMS-02 — Automatic key rotation is enabled
###############################################################################

def test_kms02_rotation_enabled(kms, key_arn: str):
    """
    Key rotation must be enabled (terraform-aws-kms module sets this by default).
    Rotation ensures the KMS key material is refreshed annually without requiring
    re-encryption of existing data.
    """
    resp = kms.get_key_rotation_status(KeyId=key_arn)
    rotation_enabled = resp.get("KeyRotationEnabled", False)
    assert rotation_enabled, (
        "Automatic key rotation is NOT enabled on this KMS key. "
        "The terraform-aws-kms module sets enable_key_rotation=true by default — "
        "check if it was overridden."
    )
    print(f"  KeyRotationEnabled: {rotation_enabled}")


###############################################################################
# KMS-03 — Key policy is readable and parseable
###############################################################################

def _get_key_policy(kms, key_arn: str) -> dict:
    """Helper: fetch and parse the default key policy."""
    raw = kms.get_key_policy(KeyId=key_arn, PolicyName="default")["Policy"]
    return json.loads(raw)


def test_kms03_policy_readable(kms, key_arn: str):
    """Key policy must be accessible and valid JSON with at least one statement."""
    policy = _get_key_policy(kms, key_arn)
    stmts = policy.get("Statement", [])
    assert stmts, "Key policy has no statements"
    print(f"  Policy has {len(stmts)} statement(s):")
    for s in stmts:
        print(f"    Sid={s.get('Sid', '(none)')}  Effect={s.get('Effect')}")


###############################################################################
# KMS-04 — Root account has kms:* (EnableIAMUserPermissions)
###############################################################################

def test_kms04_root_has_full_permissions(kms, key_arn: str):
    """
    The root account must have kms:* in the key policy.
    This activates IAM policy delegation — producer/consumer roles can be
    granted KMS access via their own IAM policies without modifying this key policy.
    """
    policy = _get_key_policy(kms, key_arn)

    for stmt in policy.get("Statement", []):
        if stmt.get("Effect") != "Allow":
            continue
        principal = stmt.get("Principal", {})
        aws_principal = principal if isinstance(principal, str) else principal.get("AWS", "")
        if isinstance(aws_principal, list):
            aws_principal = " ".join(aws_principal)

        if ":root" in aws_principal:
            actions = stmt.get("Action", [])
            if isinstance(actions, str):
                actions = [actions]
            if "kms:*" in actions or "*" in actions:
                print(f"  Sid: {stmt.get('Sid', '(none)')}")
                print(f"  Principal contains :root with kms:* — IAM delegation active")
                return

    raise AssertionError(
        "No Allow statement found granting kms:* to the root account. "
        "IAM policy delegation is not active for this key. "
        "Check the EnableIAMUserPermissions statement in the key policy."
    )


###############################################################################
# KMS-05 — sqs.amazonaws.com is a principal
###############################################################################

def _find_sqs_service_statements(policy: dict) -> list:
    """Return all Allow statements that include sqs.amazonaws.com as a principal."""
    results = []
    for stmt in policy.get("Statement", []):
        if stmt.get("Effect") != "Allow":
            continue
        principal = stmt.get("Principal", {})
        if isinstance(principal, str):
            if "sqs.amazonaws.com" in principal:
                results.append(stmt)
        elif isinstance(principal, dict):
            service = principal.get("Service", [])
            if isinstance(service, str):
                service = [service]
            if "sqs.amazonaws.com" in service:
                results.append(stmt)
    return results


def test_kms05_sqs_service_is_principal(kms, key_arn: str):
    """
    sqs.amazonaws.com must be a principal in the key policy.
    SQS calls KMS as this service identity when encrypting/decrypting messages.
    Without this, SQS cannot use the key even if the caller has IAM permissions.
    """
    policy = _get_key_policy(kms, key_arn)
    sqs_stmts = _find_sqs_service_statements(policy)
    assert sqs_stmts, (
        "No Allow statement found with Principal.Service = sqs.amazonaws.com. "
        "SQS cannot call KMS to encrypt or decrypt messages without this. "
        "Check the SQSServicePermissions statement in main.tf."
    )
    print(f"  Found {len(sqs_stmts)} statement(s) with sqs.amazonaws.com as principal")
    for s in sqs_stmts:
        print(f"    Sid: {s.get('Sid', '(none)')}")


###############################################################################
# KMS-06 — SQS service has kms:GenerateDataKey* (needed for SendMessage)
###############################################################################

def test_kms06_sqs_has_generate_data_key(kms, key_arn: str):
    """
    SQS calls kms:GenerateDataKey when a producer sends a message.
    Without this, SendMessage fails with a KMS access denied error.
    """
    policy = _get_key_policy(kms, key_arn)
    sqs_stmts = _find_sqs_service_statements(policy)
    assert sqs_stmts, "No SQS service statements found — run KMS-05 first"

    for stmt in sqs_stmts:
        actions = stmt.get("Action", [])
        if isinstance(actions, str):
            actions = [actions]
        # Match kms:GenerateDataKey or kms:GenerateDataKey* or kms:*
        has_gdk = any(
            a in ("kms:GenerateDataKey", "kms:GenerateDataKey*", "kms:*")
            or a.startswith("kms:GenerateDataKey")
            for a in actions
        )
        if has_gdk:
            print(f"  Sid: {stmt.get('Sid', '(none)')}")
            print(f"  Actions include GenerateDataKey: {actions}")
            return

    raise AssertionError(
        "No SQS service statement has kms:GenerateDataKey* in its Action list. "
        "SQS cannot encrypt messages (SendMessage) without this. "
        "Add kms:GenerateDataKey* to the SQSServicePermissions statement in main.tf."
    )


###############################################################################
# KMS-07 — SQS service has kms:Decrypt (needed for ReceiveMessage)
###############################################################################

def test_kms07_sqs_has_decrypt(kms, key_arn: str):
    """
    SQS calls kms:Decrypt when a consumer receives a message.
    Without this, ReceiveMessage returns encrypted data that cannot be decoded.
    """
    policy = _get_key_policy(kms, key_arn)
    sqs_stmts = _find_sqs_service_statements(policy)
    assert sqs_stmts, "No SQS service statements found — run KMS-05 first"

    for stmt in sqs_stmts:
        actions = stmt.get("Action", [])
        if isinstance(actions, str):
            actions = [actions]
        has_decrypt = any(
            a in ("kms:Decrypt", "kms:*") for a in actions
        )
        if has_decrypt:
            print(f"  Sid: {stmt.get('Sid', '(none)')}")
            print(f"  Actions include Decrypt: {actions}")
            return

    raise AssertionError(
        "No SQS service statement has kms:Decrypt in its Action list. "
        "SQS cannot decrypt messages (ReceiveMessage) without this. "
        "Add kms:Decrypt to the SQSServicePermissions statement in main.tf."
    )


###############################################################################
# KMS-08 — SQSServicePermissions has kms:CallerAccount condition
###############################################################################

def test_kms08_sqs_statement_has_caller_account_condition(kms, key_arn: str):
    """
    The SQS service statement must include a kms:CallerAccount condition.
    This restricts the permission to SQS queues in this account only —
    preventing other accounts' SQS from using this key.
    """
    policy = _get_key_policy(kms, key_arn)
    sqs_stmts = _find_sqs_service_statements(policy)
    assert sqs_stmts, "No SQS service statements found — run KMS-05 first"

    for stmt in sqs_stmts:
        conditions = stmt.get("Condition", {})
        for condition_type, pairs in conditions.items():
            for key, value in pairs.items():
                if key.lower() == "kms:calleraccount":
                    print(f"  Sid: {stmt.get('Sid', '(none)')}")
                    print(f"  Condition: {condition_type}.kms:CallerAccount = {value}")
                    return

    raise AssertionError(
        "No SQS service statement has a kms:CallerAccount condition. "
        "Without this, any account's SQS could use this key. "
        "Add kms:CallerAccount condition to the SQSServicePermissions statement."
    )


###############################################################################
# KMS-09 — Encryption works end-to-end (send + receive + delete)
###############################################################################

def test_kms09_e2e_encryption_works(sqs, queue_url: str):
    """
    End-to-end proof that KMS encryption is functional.

    Sends a message to the KMS-encrypted queue and receives it back.
    If KMS permissions are broken (e.g. SQS service not in key policy),
    either SendMessage or ReceiveMessage will fail with a KMS error.

    A successful roundtrip confirms:
      - kms:GenerateDataKey was granted to the SQS service (send succeeded)
      - kms:Decrypt was granted to the SQS service (receive succeeded)
      - The caller's IAM permissions allow SQS + KMS usage
    """
    global _e2e_message_body, _e2e_receipt_handle

    _e2e_message_body = f"kms-e2e-test-{uuid.uuid4()}"

    # --- Send ---
    try:
        send_resp = sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=_e2e_message_body,
        )
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        raise AssertionError(
            f"SendMessage failed with {code}. "
            "If this is a KMS error, check that sqs.amazonaws.com has kms:GenerateDataKey* "
            "in the key policy (KMS-06). "
            "If this is an AccessDenied on sqs:SendMessage, check caller IAM policy."
        ) from exc

    assert send_resp["ResponseMetadata"]["HTTPStatusCode"] == 200
    print(f"  SendMessage OK — MessageId: {send_resp['MessageId']}")

    # --- Receive ---
    time.sleep(1)  # let the message become visible

    try:
        recv_resp = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=5,
        )
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        raise AssertionError(
            f"ReceiveMessage failed with {code}. "
            "If this is a KMS error, check that sqs.amazonaws.com has kms:Decrypt "
            "in the key policy (KMS-07)."
        ) from exc

    messages = recv_resp.get("Messages", [])
    assert messages, (
        "No messages returned by ReceiveMessage. "
        "The message sent in this test should be visible."
    )

    msg = messages[0]
    assert msg["Body"] == _e2e_message_body, (
        f"Body mismatch — expected: {_e2e_message_body}, got: {msg['Body']}"
    )
    _e2e_receipt_handle = msg["ReceiptHandle"]
    print(f"  ReceiveMessage OK — body matches")

    # --- Delete (cleanup) ---
    del_resp = sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=_e2e_receipt_handle,
    )
    assert del_resp["ResponseMetadata"]["HTTPStatusCode"] == 200
    print(f"  DeleteMessage OK — message cleaned up")
    print(f"  KMS encryption is fully functional (GenerateDataKey + Decrypt both worked)")


###############################################################################
# Main
###############################################################################

def main() -> int:
    global PASS_COUNT, FAIL_COUNT

    print("\n" + "=" * 60)
    print("simple-sqs-with-tls — KMS Permission Test Suite")
    print("Verifies KMS key policy is correctly configured for SQS encryption")
    print("=" * 60)

    outputs    = get_terraform_outputs()
    key_arn    = outputs.get("kms_key_arn", {}).get("value", "")
    queue_url  = outputs.get("queue_url", {}).get("value", "")
    aws_region = outputs.get("aws_region", {}).get("value", "us-east-2")

    if not key_arn:
        print("ERROR: kms_key_arn not found in terraform outputs.")
        print("  Run 'terraform apply' first, or set KMS_KEY_ARN env var.")
        return 1

    if not queue_url:
        print("ERROR: queue_url not found in terraform outputs.")
        print("  Run 'terraform apply' first, or set QUEUE_URL env var.")
        return 1

    print(f"\nKMS Key ARN : {key_arn}")
    print(f"Queue URL   : {queue_url}")
    print(f"Region      : {aws_region}")

    kms = boto3.client("kms", region_name=aws_region)
    sqs = boto3.client("sqs", region_name=aws_region)

    tests = [
        ("KMS-01 Key exists and is Enabled",
            lambda: test_kms01_key_enabled(kms, key_arn)),
        ("KMS-02 Automatic key rotation is enabled",
            lambda: test_kms02_rotation_enabled(kms, key_arn)),
        ("KMS-03 Key policy is readable and parseable",
            lambda: test_kms03_policy_readable(kms, key_arn)),
        ("KMS-04 Root account has kms:* (IAM delegation active)",
            lambda: test_kms04_root_has_full_permissions(kms, key_arn)),
        ("KMS-05 sqs.amazonaws.com is a key policy principal",
            lambda: test_kms05_sqs_service_is_principal(kms, key_arn)),
        ("KMS-06 SQS service has kms:GenerateDataKey* (SendMessage path)",
            lambda: test_kms06_sqs_has_generate_data_key(kms, key_arn)),
        ("KMS-07 SQS service has kms:Decrypt (ReceiveMessage path)",
            lambda: test_kms07_sqs_has_decrypt(kms, key_arn)),
        ("KMS-08 SQS service statement has kms:CallerAccount condition",
            lambda: test_kms08_sqs_statement_has_caller_account_condition(kms, key_arn)),
        ("KMS-09 Encryption works end-to-end (send + receive + delete)",
            lambda: test_kms09_e2e_encryption_works(sqs, queue_url)),
    ]

    for name, fn in tests:
        run_test(name, fn)

    total = PASS_COUNT + FAIL_COUNT
    print("\n" + "=" * 60)
    print("KMS Test Summary — simple-sqs-with-tls")
    print("=" * 60)
    print(f"Total: {PASS_COUNT}/{total} passed")

    if FAIL_COUNT == 0:
        print("\nAll KMS tests passed!")
        print("CONCLUSION: KMS key policy is correctly configured.")
        print("  - sqs.amazonaws.com can GenerateDataKey (SendMessage works)")
        print("  - sqs.amazonaws.com can Decrypt (ReceiveMessage works)")
        print("  - Root account enables IAM delegation for caller roles")
        print("  - CallerAccount condition restricts to this account only")
        return 0
    else:
        print(f"\n{FAIL_COUNT} test(s) failed.")
        print("\nDiagnosis hints:")
        print("  KMS-01/02 failed  → key state issue, check AWS Console → KMS")
        print("  KMS-03 failed     → caller needs kms:GetKeyPolicy IAM permission")
        print("  KMS-04 failed     → EnableIAMUserPermissions statement missing in key policy")
        print("  KMS-05/06/07 failed → SQSServicePermissions statement missing or incomplete")
        print("  KMS-08 failed     → kms:CallerAccount condition missing (cross-account risk)")
        print("  KMS-09 failed     → end-to-end broken; check caller IAM + key policy together")
        return 1


if __name__ == "__main__":
    sys.exit(main())
