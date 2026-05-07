# EMR AMI Enforcement — Governance Design & Remediation
**Document Version:** 1.1 | **Date:** 2026-04-23 | **Status:** Draft — Pending Security Review

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Root Cause Analysis](#2-root-cause-analysis)
3. [What is a Service-Linked Role (SLR)?](#3-what-is-a-service-linked-role-slr)
4. [Implementation Plan](#4-implementation-plan)
5. [Verification Script](#5-verification-script)
6. [Operations Runbook](#6-operations-runbook)
7. [Defence-in-Depth Summary](#7-defence-in-depth-summary)
8. [Validation Checklist](#8-validation-checklist)
9. [AWS Documentation References](#9-aws-documentation-references)

---

## 1. Problem Statement

### 1.1 Context

The organisation operates approximately 400 AWS accounts under AWS Organizations. A private AMI owned by external account `286198878708` is used by Amazon EMR for specific ClaimsData Prasanth workloads. The three approved accounts — `111111111111` (DEV), `222222222222` (TST), and `333333333333` (PRD) — are the only accounts permitted to launch EC2 instances using this AMI.

### 1.2 Observed Behaviour

Account `444444444444` successfully launches an EMR cluster using the AMI owned by `286198878708` even though:

- An SCP (`scp-enforcement-for-erie-allowed-aws-emr-amis`, policy ID `p-xxxxxxxxxxxx`) is attached to the account with an explicit `ec2:RunInstances` deny condition targeting this AMI owner.
- The account is **not** listed in the SCP's exemption list (`StringNotEquals` on `aws:PrincipalAccount`).

### 1.3 Expected Behaviour

Any EMR cluster creation attempt in accounts outside the three approved accounts that references AMI owner `286198878708` should fail at the EC2 layer — regardless of how the `ec2:RunInstances` call is made (directly or via a managed AWS service).

### 1.4 Scope of Impact

| Account | Expected | Actual |
|---|---|---|
| `111111111111` (DEV) | ✅ Allow | ✅ Works |
| `222222222222` (TST) | ✅ Allow | ✅ Works |
| `333333333333` (PRD) | ✅ Allow | ✅ Works |
| `444444444444` | ❌ Block | ✅ **Incorrectly allowed** |
| All other ~396 accounts | ❌ Block | ⚠️ Unknown — assumed incorrectly allowed |

---

## 2. Root Cause Analysis

The failure has **two compounding causes** — either one alone would result in the observed bypass.

---

### Cause 1 — EC2 Declarative Policy Is Scoped at Org Root (Too Broad)

The EC2 Declarative Policy (AMI Allowed Images Policy) that permits use of AMI owner `286198878708` is attached at the **Organisation Root**. This means every account in the organisation — all 400 of them — inherits the ALLOW for this AMI at the EC2 control plane layer.

```
Org Root
└── Declarative Policy (ALLOW AMI owner 286198878708)
    └── Inherited by ALL 400 accounts
        └── EC2 control plane grants every account permission to use the AMI
```

This is the primary enforcement gap. The Declarative Policy is the layer that the EC2 control plane actually evaluates — and it currently says "allowed" for everyone.

---

### Cause 2 — SCPs Do Not Apply to Service-Linked Roles (SLR Bypass)

When Amazon EMR launches EC2 instances, it does so via its **Service-Linked Role** `AWSServiceRoleForEMR`. AWS explicitly excludes SLRs from SCP evaluation — by design, at the platform level. This means the SCP deny on `ec2:RunInstances` is **never evaluated** for any EMR-initiated EC2 call, regardless of what the SCP contains or which accounts it is attached to.

```
User calls:  elasticmapreduce:RunJobFlow
               ↓
EMR assumes: AWSServiceRoleForEMR  ←  SLR — EXEMPT from all SCPs
               ↓
SLR calls:   ec2:RunInstances       ←  SCP evaluation SKIPPED entirely
               ↓
EC2 checks:  Declarative Policy     ←  Sees "ALLOW" (inherited from Org Root)
               ↓
             Instance launches ✅ (incorrectly)
```

---

### Cause 3 — Secondary Issue: Wrong Condition Key in SCP

The existing SCP uses the condition key `ec2:Owner`. The correct, currently documented condition key for AMI owner enforcement is `ec2:ImageOwner`. While `ec2:Owner` may evaluate in some contexts, it is not the canonical key and can produce inconsistent behaviour.

| Condition Key | Status |
|---|---|
| `ec2:Owner` | Legacy — inconsistent context evaluation |
| `ec2:ImageOwner` | ✅ Current — use this |

---

### Root Cause Summary

| Cause | Control Affected | Effect |
|---|---|---|
| Declarative Policy at Org Root | All 400 accounts inherit AMI ALLOW | EC2 permits launch in every account |
| SLR exempt from SCPs | `AWSServiceRoleForEMR` | SCP deny never fires for EMR launches |
| Wrong condition key (`ec2:Owner`) | SCP | Inconsistent evaluation even for non-SLR calls |

**The SCP was always the wrong primary control for managed services.** EC2 Declarative Policies are the correct enforcement layer because they are evaluated at the EC2 control plane — a layer even SLRs cannot bypass.

---

## 3. What is a Service-Linked Role (SLR)?

### 3.1 Definition

A **Service-Linked Role (SLR)** is a special type of IAM role with the following properties:

- **Created and owned by AWS**, not the customer.
- **Trust policy and permissions are predefined by the AWS service** — customers cannot modify them.
- **Cannot be deleted** while the associated service is actively using it.
- **Scoped to a specific AWS service** — only that service can assume it.

### 3.2 EMR's SLR

When you create an Amazon EMR cluster, AWS automatically provisions and uses the following SLR to perform infrastructure operations on your behalf:

```
Role Name:  AWSServiceRoleForEMR
ARN:        arn:aws:iam::<account-id>:role/aws-service-role/
              elasticmapreduce.amazonaws.com/AWSServiceRoleForEMR
Trust:      elasticmapreduce.amazonaws.com
```

This role calls `ec2:RunInstances`, `ec2:DescribeInstances`, `ec2:TerminateInstances`, and other EC2 APIs on behalf of the EMR service. You do not create it, assign it, or control its permissions.

### 3.3 Why SCPs Cannot Block SLRs

This is not a bug or an edge case — it is an explicit, documented AWS design decision:

> *"SCPs don't affect service-linked role policies. Service-linked roles enable other AWS services to integrate with AWS Organizations and can't be restricted by SCPs."*
> — AWS Organizations User Guide

The rationale is reliability: if SCPs could block SLRs, a misconfigured SCP could silently break managed services across an entire organisation. AWS made the deliberate architectural choice to keep managed service operations outside SCP scope.

### 3.4 Practical Implication for Platform Engineers

Any governance control that relies on SCP deny conditions to block **managed AWS services** (EMR, RDS, EKS, Redshift, etc.) will fail silently for that service's SLR-initiated calls. The SLR bypasses the SCP evaluation path entirely — no error is thrown, no CloudTrail deny event is recorded, the instance simply launches.

The correct control plane for this type of enforcement is **EC2 Declarative Policies**, which are evaluated at the EC2 API layer itself — a layer that SLRs must pass through and cannot bypass.

---

## 4. Implementation Plan

### Prerequisites

- AWS Organizations management account access (or delegated admin for policies).
- Existing AUDIT-mode Declarative Policy at Org Root — confirm it is in AUDIT, not ENFORCE.
- Existing SCP policy ID (`p-xxxxxxxxxxxx`) for the backstop update.

---

### Phase 1 — Create the ENFORCE Declarative Policy

Create a new Declarative Policy in ENFORCE mode. This will be attached directly to the three approved accounts only — **not** the Org Root.

Save the following as `enforce-declarative-policy.json`:

```json
{
  "ec2_attributes": {
    "@@operators_allowed_for_child_policies": ["@@none"],
    "allowed_images_settings": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      "state": {
        "@@operators_allowed_for_child_policies": ["@@none"],
        "@@assign": "enabled"
      },
      "image_criteria": {
        "@@operators_allowed_for_child_policies": ["@@none"],
        "@@append": [
          {
            "allowed_image_owners": {
              "@@assign": ["286198878708"]
            }
          }
        ]
      }
    }
  }
}
```

```bash
# Create the ENFORCE declarative policy
aws organizations create-policy \
  --name "emr-ami-enforce-claimsdata-erie" \
  --description "ENFORCE: Permits EC2 use of AMI owner 286198878708 for ClaimsData Prasanth accounts. Attach to approved accounts directly only." \
  --type EC2_ATTRIBUTE_POLICY \
  --content file://enforce-declarative-policy.json \
  --query 'Policy.PolicySummary.Id' \
  --output text

# Store the returned policy ID — you will need it in Phase 2
# e.g., p-abc12345
```

---

### Phase 2 — Attach ENFORCE Policy Directly to Approved Accounts

```bash
ENFORCE_POLICY_ID="p-abc12345"   # Replace with output from Phase 1

# DEV account
aws organizations attach-policy \
  --policy-id ${ENFORCE_POLICY_ID} \
  --target-id 111111111111

# TST account
aws organizations attach-policy \
  --policy-id ${ENFORCE_POLICY_ID} \
  --target-id 222222222222

# PRD account
aws organizations attach-policy \
  --policy-id ${ENFORCE_POLICY_ID} \
  --target-id 333333333333

# Verify all three attachments
aws organizations list-targets-for-policy \
  --policy-id ${ENFORCE_POLICY_ID} \
  --query 'Targets[*].{Id:TargetId,Type:Type}' \
  --output table
```

---

### Phase 3 — Confirm Root Declarative Policy Is AUDIT Only

The existing Org Root Declarative Policy must remain in AUDIT (report-only) mode. Confirm it does not have `"state": "enabled"` (ENFORCE) in its content.

```bash
# List EC2 attribute policies at org root
aws organizations list-policies \
  --filter EC2_ATTRIBUTE_POLICY \
  --query 'Policies[*].{Id:Id,Name:Name}' \
  --output table

# Describe the root-level policy and confirm mode
aws organizations describe-policy \
  --policy-id <root-declarative-policy-id> \
  --query 'Policy.Content' \
  --output text | python3 -m json.tool
# state should be "audit" not "enabled"
```

---

### Phase 4 — Update the SCP Backstop

Update the existing SCP to fix the condition key and add the `aws:ViaAWSService` guard so it only fires for direct human/role calls (not SLR calls, which are already handled by the Declarative Policy).

Save as `updated-scp.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyEmrAmisOutsideClaimsDataAccounts",
      "Effect": "Deny",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet"
      ],
      "Resource": "arn:aws:ec2:*::image/*",
      "Condition": {
        "StringEquals": {
          "ec2:ImageOwner": "286198878708"
        },
        "StringNotEquals": {
          "aws:PrincipalAccount": [
            "111111111111",
            "222222222222",
            "333333333333"
          ]
        },
        "BoolIfExists": {
          "aws:ViaAWSService": "false"
        }
      }
    }
  ]
}
```

```bash
# Update the SCP
aws organizations update-policy \
  --policy-id p-xxxxxxxxxxxx \
  --content file://updated-scp.json

# Confirm the update
aws organizations describe-policy \
  --policy-id p-xxxxxxxxxxxx \
  --query 'Policy.Content' \
  --output text | python3 -m json.tool
```

**Key changes from the original SCP:**

| Field | Before | After | Reason |
|---|---|---|---|
| Condition key | `ec2:Owner` | `ec2:ImageOwner` | Correct documented key |
| `aws:ViaAWSService` | Missing | `BoolIfExists: false` | Skips SLR calls gracefully |
| Exemption list | Unchanged | Unchanged | Correct — only 3 approved accounts |

---

## 5. Verification Script

Run this from the management account after completing all four phases. It cross-account assumes a read role into each target account and checks the effective Declarative Policy settings.

```python
#!/usr/bin/env python3
"""
emr_ami_policy_verify.py

Verifies effective EC2 Declarative Policy (AMI Allowed Images) settings
across approved and blocked accounts post-implementation.

Requirements:
  - boto3
  - Read/assume-role access from management account into each target account
  - IAM role name must exist in each target account (default: PlatformEngineeringReadOnly)

Usage:
  python3 emr_ami_policy_verify.py
  python3 emr_ami_policy_verify.py --role MyReadRole --region eu-west-1
"""

import argparse
import boto3
import json
import logging
import sys
from botocore.exceptions import ClientError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S"
)
logger = logging.getLogger(__name__)

APPROVED_ACCOUNTS = {
    "111111111111": "DEV — ClaimsData Prasanth",
    "222222222222": "TST — ClaimsData Prasanth",
    "333333333333": "PRD — ClaimsData Prasanth",
}

BLOCKED_ACCOUNTS = {
    "444444444444": "Other — Should be blocked",
}

TARGET_AMI_OWNER = "286198878708"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify EMR AMI Declarative Policy enforcement")
    parser.add_argument("--role", default="PlatformEngineeringReadOnly", help="IAM role name to assume")
    parser.add_argument("--region", default="ap-southeast-2", help="AWS region")
    parser.add_argument("--session-name", default="emr-ami-policy-verify", help="STS session name")
    return parser.parse_args()


def assume_role(account_id: str, role_name: str, session_name: str) -> dict:
    sts = boto3.client("sts")
    try:
        response = sts.assume_role(
            RoleArn=f"arn:aws:iam::{account_id}:role/{role_name}",
            RoleSessionName=session_name,
            DurationSeconds=900
        )
        return response["Credentials"]
    except ClientError as e:
        logger.error(f"  Failed to assume role in {account_id}: {e.response['Error']['Message']}")
        return {}


def get_allowed_images_settings(account_id: str, creds: dict, region: str) -> dict:
    ec2 = boto3.client(
        "ec2",
        region_name=region,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"]
    )
    try:
        response = ec2.get_allowed_images_settings()
        criteria = response.get("ImageCriteria", [])
        allowed_owners = [
            owner
            for criterion in criteria
            for owner in criterion.get("AllowedImageOwners", [])
        ]
        state = response.get("State", "unknown")
        return {
            "state": state,
            "allowed_owners": allowed_owners,
            "target_ami_allowed": TARGET_AMI_OWNER in allowed_owners,
            "raw_criteria": criteria
        }
    except ClientError as e:
        return {
            "error": e.response["Error"]["Message"],
            "state": "error",
            "target_ami_allowed": None
        }


def check_account(account_id: str, label: str, expected_allowed: bool,
                  role_name: str, session_name: str, region: str) -> dict:
    logger.info(f"Checking {account_id} ({label})")
    creds = assume_role(account_id, role_name, session_name)
    if not creds:
        return {"account_id": account_id, "label": label, "status": "ASSUME_ROLE_FAILED"}

    settings = get_allowed_images_settings(account_id, creds, region)

    if "error" in settings:
        status = "ERROR"
        icon = "⚠️"
    elif settings["target_ami_allowed"] == expected_allowed:
        status = "PASS"
        icon = "✅"
    else:
        status = "FAIL"
        icon = "❌"

    result = {
        "account_id": account_id,
        "label": label,
        "expected_allowed": expected_allowed,
        "actual_allowed": settings.get("target_ami_allowed"),
        "state": settings.get("state"),
        "allowed_owners": settings.get("allowed_owners", []),
        "status": status
    }

    logger.info(
        f"  {icon}  [{status}]  state={result['state']}  "
        f"ami_owner_allowed={result['actual_allowed']}  "
        f"(expected={expected_allowed})"
    )
    return result


def main():
    args = parse_args()
    results = []
    all_pass = True

    logger.info("=" * 70)
    logger.info("EMR AMI Declarative Policy Verification")
    logger.info(f"Target AMI Owner: {TARGET_AMI_OWNER}")
    logger.info(f"Region: {args.region} | Role: {args.role}")
    logger.info("=" * 70)

    logger.info("\n--- Approved Accounts (expect: ALLOW) ---")
    for account_id, label in APPROVED_ACCOUNTS.items():
        result = check_account(
            account_id, label, True, args.role, args.session_name, args.region
        )
        results.append(result)
        if result["status"] != "PASS":
            all_pass = False

    logger.info("\n--- Blocked Accounts (expect: DENY) ---")
    for account_id, label in BLOCKED_ACCOUNTS.items():
        result = check_account(
            account_id, label, False, args.role, args.session_name, args.region
        )
        results.append(result)
        if result["status"] != "PASS":
            all_pass = False

    logger.info("\n" + "=" * 70)
    logger.info("SUMMARY")
    logger.info("=" * 70)
    for r in results:
        icon = "✅" if r["status"] == "PASS" else "❌"
        logger.info(f"  {icon}  {r['account_id']}  ({r['label']})  →  {r['status']}")

    logger.info("=" * 70)
    if all_pass:
        logger.info("✅  ALL CHECKS PASSED — Declarative Policy enforcement is correct")
        sys.exit(0)
    else:
        logger.error("❌  ONE OR MORE CHECKS FAILED — Review output above")
        sys.exit(1)


if __name__ == "__main__":
    main()
```

---

## 6. Operations Runbook

### 6.1 Adding a New Approved Account

When a new account is onboarded and requires access to the EMR AMI:

```bash
# Step 1 — Get the ENFORCE policy ID
ENFORCE_POLICY_ID=$(aws organizations list-policies \
  --filter EC2_ATTRIBUTE_POLICY \
  --query "Policies[?Name=='emr-ami-enforce-claimsdata-erie'].Id" \
  --output text)

echo "ENFORCE policy ID: ${ENFORCE_POLICY_ID}"

# Step 2 — Attach to the new account
NEW_ACCOUNT_ID="111122223333"

aws organizations attach-policy \
  --policy-id ${ENFORCE_POLICY_ID} \
  --target-id ${NEW_ACCOUNT_ID}

# Step 3 — Add account to SCP exemption list
# Edit updated-scp.json — add NEW_ACCOUNT_ID to the StringNotEquals array
# Then update:
aws organizations update-policy \
  --policy-id p-xxxxxxxxxxxx \
  --content file://updated-scp.json

# Step 4 — Verify effective settings from within the new account
aws ec2 get-allowed-images-settings \
  --region ap-southeast-2
# Expected: state=enabled, ImageCriteria includes owner 286198878708
```

---

### 6.2 Removing an Approved Account

When an account should no longer have access to the EMR AMI:

```bash
# Step 1 — Detach ENFORCE policy from the account
aws organizations detach-policy \
  --policy-id ${ENFORCE_POLICY_ID} \
  --target-id <account-id>

# Step 2 — Remove account from SCP exemption list
# Edit updated-scp.json — remove account from StringNotEquals array
aws organizations update-policy \
  --policy-id p-xxxxxxxxxxxx \
  --content file://updated-scp.json

# Step 3 — Verify any active EMR clusters are terminated in that account
aws emr list-clusters \
  --active \
  --region ap-southeast-2 \
  --query 'Clusters[*].{Id:Id,Name:Name,State:Status.State}'

# Step 4 — Confirm effective policy is now blocking
aws ec2 get-allowed-images-settings \
  --region ap-southeast-2
# Expected: state=audit (inherited from root) — no ENFORCE override
```

---

### 6.3 Troubleshooting Table

| Symptom | Likely Cause | Investigation | Resolution |
|---|---|---|---|
| EMR still launches in blocked account | ENFORCE policy accidentally attached to that account or its OU | `aws organizations list-policies-for-target --target-id <account-id> --filter EC2_ATTRIBUTE_POLICY` | Detach ENFORCE policy from blocked account |
| EMR fails in approved account | ENFORCE policy not attached, or attached to wrong account | `aws ec2 get-allowed-images-settings` from within account | Re-attach ENFORCE policy to correct account ID |
| Direct EC2 launch succeeds in blocked account | SCP not attached, or `aws:ViaAWSService` condition missing | `aws organizations list-policies-for-target --target-id <account-id> --filter SERVICE_CONTROL_POLICY` | Verify SCP attachment and correct condition keys |
| CloudTrail shows RunInstances from SLR in blocked account | Declarative Policy enforcement not effective — ENFORCE policy leak | Check all parent OUs for accidental ENFORCE policy attachment | Remove ENFORCE policy from any OU/root it should not be on |
| `get-allowed-images-settings` returns empty | AUDIT mode inherited — no ENFORCE policy | Expected for blocked accounts | No action needed if intent is to block |

---

### 6.4 Key CloudTrail Queries

**Find all RunInstances calls in a given account (last 24 hours):**

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --region ap-southeast-2 \
  --query 'Events[*].{
    Time:EventTime,
    User:Username,
    Source:EventSource,
    RequestID:EventId
  }' \
  --output table
```

**Determine if a RunInstances call was from an SLR (EMR):**

```bash
# Get the full event detail — look for userIdentity.type = "AssumedRole"
# and userIdentity.sessionContext.sessionIssuer.userName = "AWSServiceRoleForEMR"
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --region ap-southeast-2 \
  --query 'Events[*].CloudTrailEvent' \
  --output text | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        event = json.loads(line)
        identity = event.get('userIdentity', {})
        issuer = identity.get('sessionContext', {}).get('sessionIssuer', {})
        print(f\"Time: {event.get('eventTime')}  Caller: {issuer.get('userName', identity.get('userName', 'N/A'))}  Type: {identity.get('type')}\")
    except Exception:
        pass
"
```

**Confirm which AMI was used in a RunInstances call:**

```bash
# Search CloudTrail for RunInstances, then extract AMI ID from requestParameters
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --region ap-southeast-2 \
  --query 'Events[*].CloudTrailEvent' \
  --output text | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        event = json.loads(line)
        ami = event.get('requestParameters', {}).get('imageId', 'N/A')
        account = event.get('recipientAccountId', 'N/A')
        time = event.get('eventTime', 'N/A')
        print(f'Time: {time}  Account: {account}  AMI: {ami}')
    except Exception:
        pass
"
```

---

## 7. Defence-in-Depth Summary

### Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  PRIMARY — EC2 Declarative Policy (AUDIT at root, ENFORCE       │
│            directly on approved accounts)                       │
│                                                                 │
│  What it catches: ALL ec2:RunInstances calls including SLRs     │
│  Can be bypassed? NO — evaluated at EC2 control plane           │
│  Applies to EMR?  YES — SLR must pass through EC2 API           │
├─────────────────────────────────────────────────────────────────┤
│  SECONDARY — SCP Deny (ec2:RunInstances / ec2:CreateFleet)      │
│              with aws:ViaAWSService=false guard                 │
│                                                                 │
│  What it catches: Direct human/console EC2 launches (non-SLR)  │
│  Can be bypassed? YES — by SLRs (by AWS design)                 │
│  Applies to EMR?  NO — SLR bypasses SCP                         │
│  Still useful?    YES — backstop for console/IaC direct calls   │
├─────────────────────────────────────────────────────────────────┤
│  TERTIARY — EventBridge + CloudTrail Anomaly Alerts             │
│                                                                 │
│  What it catches: Any unexpected RunInstances in non-approved   │
│                   accounts — alerting + auto-terminate option   │
│  Can be bypassed? NO (detection only, not prevention)           │
│  Response time:   Seconds after event                           │
└─────────────────────────────────────────────────────────────────┘
```

### Control Comparison Matrix

| Control | Blocks SLR? | Blocks Direct EC2? | Blocks EMR? | Bypassable? | Layer |
|---|---|---|---|---|---|
| EC2 Declarative Policy (ENFORCE) | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No | EC2 Control Plane |
| SCP Deny | ❌ No | ✅ Yes | ❌ No | ✅ Yes (via SLR) | IAM |
| EventBridge + Lambda | N/A | N/A | N/A | N/A | Detection |
| AMI Launch Permissions | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No | EC2 Control Plane |

> **Note on AMI Launch Permissions:** This would be the single strongest control, enforced directly on the AMI itself. However, since the AMI is owned by external account `286198878708` which is not part of the organisation, this lever is not available.

### Why Declarative Policy Is the Right Primary Control

SCPs operate at the IAM evaluation layer — they restrict what IAM principals can do. SLRs are, by AWS design, outside the IAM principal evaluation chain for SCP purposes. EC2 Declarative Policies operate at the EC2 API layer itself, which every caller — including SLRs — must pass through. This is why the Declarative Policy is the only control that can reliably block managed service AMI usage across all caller types.

---

## 8. Validation Checklist

### Policy Configuration

- [ ] ENFORCE Declarative Policy (`emr-ami-enforce-claimsdata-erie`) created with `allowed_image_owners: ["286198878708"]`
- [ ] ENFORCE policy attached **directly** to account `111111111111` (DEV)
- [ ] ENFORCE policy attached **directly** to account `222222222222` (TST)
- [ ] ENFORCE policy attached **directly** to account `333333333333` (PRD)
- [ ] ENFORCE policy is **NOT** attached to any OU or Org Root
- [ ] Root Declarative Policy confirmed as **AUDIT mode** only (not ENFORCE)
- [ ] SCP `p-xxxxxxxxxxxx` updated — `ec2:Owner` replaced with `ec2:ImageOwner`
- [ ] SCP `p-xxxxxxxxxxxx` updated — `aws:ViaAWSService: false` condition added

### Functional Testing

- [ ] EMR cluster creation **succeeds** in `111111111111` (DEV)
- [ ] EMR cluster creation **succeeds** in `222222222222` (TST)
- [ ] EMR cluster creation **succeeds** in `333333333333` (PRD)
- [ ] EMR cluster creation **fails** in `444444444444` with EC2 Declarative Policy error
- [ ] Direct `ec2:RunInstances` with AMI owner `286198878708` **fails** in `444444444444` via SCP deny
- [ ] Verification script exits with code 0 (all checks PASS)

### Audit & Operations

- [ ] CloudTrail reviewed — no unexpected RunInstances in blocked accounts post-implementation
- [ ] `aws ec2 get-allowed-images-settings` run from each approved account — shows ENFORCE + correct owner
- [ ] `aws ec2 get-allowed-images-settings` run from `444444444444` — shows AUDIT only, no ENFORCE
- [ ] Runbook shared with on-call team and linked from the platform wiki
- [ ] Change record raised, approved, and post-implementation review scheduled

---

## 9. AWS Documentation References

### EC2 Declarative Policies (Primary Control)

1. [Declarative policies for EC2 — AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html)
2. [AMI Allowed Images Policy (EC2 User Guide)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-allowed-amis.html)
3. [GetAllowedImagesSettings API Reference](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_GetAllowedImagesSettings.html)
4. [Declarative policy effective policy evaluation and inheritance](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative_effective.html)
5. [Attaching and detaching Declarative Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative_attach-detach.html)

### Service Control Policies

6. [Service control policies (SCPs) overview — AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
7. [SCP evaluation and effect on member accounts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_evaluation.html)
8. [SCPs do not affect service-linked roles (limitations section)](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html#orgs_manage_policies_scps_limitations)
9. [ec2:ImageOwner — IAM condition key reference for EC2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2.html)
10. [aws:ViaAWSService global condition key](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-viaawsservice)

### Service-Linked Roles

11. [Service-linked roles overview — IAM User Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/using-service-linked-roles.html)
12. [AWSServiceRoleForEMR — EMR service-linked role documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/using-service-linked-roles.html)

### IAM Policy Evaluation

13. [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
14. [Cross-account policy evaluation for organization member accounts](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic-cross-account.html)

### Amazon EMR

15. [Using a custom AMI with Amazon EMR](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-custom-ami.html)

---

*Document maintained by Platform Engineering. For changes, raise a ticket in the platform backlog or open a MR against this document in the governance repository.*
