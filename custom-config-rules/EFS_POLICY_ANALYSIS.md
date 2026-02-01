# EFS Policy Analysis - Compliance Gap Identified

## Overview

This document analyzes a deployed EFS file system policy that was marked **COMPLIANT** by the Lambda rule, but has a **security gap** that should have been flagged.

## Deployed Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OnlyallowAccessViaMountTargetandpermitmountaccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:root"
      },
      "Action": [
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientMount"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "elasticfilesystem:AccessedViaMountTarget": "true"
        }
      }
    },
    {
      "Sid": "DenyUnencryptedAccessAndUploads",
      "Effect": "Deny",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:root"
      },
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

---

## Current Lambda Validation (What IS Checked)

| Check | Status | Finding |
|-------|--------|---------|
| Policy exists | ✅ PASS | Policy is attached |
| Effect = "Deny" | ✅ PASS | Second statement has Deny |
| Condition: `aws:SecureTransport = "false"` | ✅ PASS | Condition present |
| Action covers EFS client actions | ✅ PASS | Action = `*` covers all |

**Result:** COMPLIANT ✅

---

## Security Gap Identified (What is NOT Checked)

### Critical Issue: Principal Restriction

The Deny statement has:
```json
"Principal": {
  "AWS": "arn:aws:iam::111111111111:root"
}
```

**Problem:** The TLS enforcement **only applies to this specific AWS account**!

| Scenario | TLS Required? |
|----------|---------------|
| Access from `arn:aws:iam::111111111111:root` | ✅ Yes (Deny applies) |
| Access from `arn:aws:iam::222222222222:root` | ❌ **No** (Deny doesn't apply) |
| Access from any IAM role in another account | ❌ **No** (Deny doesn't apply) |
| Access from `*` (anonymous) | ❌ **No** (Deny doesn't apply) |

### Why This Matters

A properly scoped TLS enforcement policy should have:
```json
"Principal": "*"
```

This ensures TLS is required for **ALL** access, not just from a specific account.

---

## Missing Validation in Lambda Function

### 1. Principal Validation (HIGH Priority)

**Current behavior:** Lambda does NOT check the Principal field
**Should check:** Principal should be `*` or cover all intended access patterns

```python
# MISSING CHECK - Should be added
def _validates_principal(statement: Dict[str, Any]) -> bool:
    """
    Check if Deny statement applies to all principals.
    
    For TLS enforcement to be effective, the Deny must apply to:
    - Principal: "*" (all principals)
    - Or Principal: {"AWS": "*"} (all AWS principals)
    """
    principal = statement.get('Principal', {})
    
    # Wildcard principal - applies to all
    if principal == '*':
        return True
    
    # AWS wildcard - applies to all AWS principals
    if isinstance(principal, dict):
        aws_principal = principal.get('AWS', '')
        if aws_principal == '*':
            return True
        if isinstance(aws_principal, list) and '*' in aws_principal:
            return True
    
    # Specific principal - TLS enforcement is scoped/limited
    return False
```

### 2. Resource Validation (MEDIUM Priority)

**Current behavior:** Lambda does NOT check the Resource field
**Should check:** Resource should be `*` or the specific EFS ARN

### 3. NotPrincipal Handling (LOW Priority)

**Current behavior:** Lambda does NOT handle NotPrincipal
**Should check:** NotPrincipal should not exclude legitimate users

---

## Compliant vs Non-Compliant Policy Examples

### ✅ COMPLIANT: Universal TLS Enforcement

```json
{
  "Sid": "DenyUnencryptedAccess",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

### ❌ NON-COMPLIANT: Scoped TLS Enforcement (Current Policy)

```json
{
  "Sid": "DenyUnencryptedAccess",
  "Effect": "Deny",
  "Principal": {
    "AWS": "arn:aws:iam::111111111111:root"
  },
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why it's non-compliant:** Only enforces TLS for one specific account, not all access.

---

## Recommended Lambda Function Enhancement

### Add Principal Validation to `is_secure_transport_enforced()`

```python
def is_secure_transport_enforced(policy: Dict[str, Any], file_system_id: str = None) -> bool:
    statements = policy.get('Statement', [])
    
    for statement in statements:
        effect = statement.get('Effect', '')
        condition = statement.get('Condition', {})
        
        if effect != 'Deny':
            continue
        
        # Check SecureTransport condition
        if not _has_secure_transport_condition(condition):
            continue
        
        # Check actions cover EFS client actions
        if not _validates_client_actions(statement):
            continue
        
        # NEW: Check principal is universal (not scoped)
        if not _validates_principal_is_universal(statement):
            logger.warning(
                "Found Deny with SecureTransport=false but Principal is scoped, not universal"
            )
            continue
        
        return True
    
    return False


def _validates_principal_is_universal(statement: Dict[str, Any]) -> bool:
    """Check if Principal applies to all access (not scoped to specific accounts)."""
    principal = statement.get('Principal')
    
    # Wildcard - applies to all
    if principal == '*':
        return True
    
    # AWS wildcard
    if isinstance(principal, dict):
        aws_principal = principal.get('AWS')
        if aws_principal == '*':
            return True
        if isinstance(aws_principal, list) and '*' in aws_principal:
            return True
    
    # Scoped principal - TLS enforcement is limited
    logger.warning(f"Principal is scoped: {principal}")
    return False
```

---

## Test Cases to Add

| Test Case | Principal | Expected Result |
|-----------|-----------|-----------------|
| Universal Principal | `"*"` | COMPLIANT |
| AWS Wildcard Principal | `{"AWS": "*"}` | COMPLIANT |
| Specific Account Principal | `{"AWS": "arn:aws:iam::111111111111:root"}` | **NON_COMPLIANT** |
| Multiple Accounts (no wildcard) | `{"AWS": ["arn:...:111", "arn:...:222"]}` | **NON_COMPLIANT** |
| Multiple Accounts (with wildcard) | `{"AWS": ["*", "arn:...:111"]}` | COMPLIANT |

---

## Summary of Findings

| Category | Finding | Severity |
|----------|---------|----------|
| **Principal Validation** | Lambda does NOT check if Deny applies to all principals | 🔴 HIGH |
| **Current Policy** | TLS is only enforced for one specific account | 🔴 HIGH |
| **False Positive** | Policy was marked COMPLIANT but has security gap | 🔴 HIGH |
| **Resource Validation** | Lambda does NOT check Resource field | 🟡 MEDIUM |

---

## Action Items

### Immediate (Fix False Positive)

1. ☐ Add `_validates_principal_is_universal()` function to Lambda
2. ☐ Update `is_secure_transport_enforced()` to call principal validation
3. ☐ Add test cases for scoped vs universal principals
4. ☐ Redeploy Lambda function

### Policy Remediation

1. ☐ Update EFS policy to use `"Principal": "*"`
2. ☐ Re-evaluate EFS file system after policy update
3. ☐ Verify new evaluation shows COMPLIANT

---

## Corrected EFS Policy (Recommended)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OnlyallowAccessViaMountTargetandpermitmountaccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:root"
      },
      "Action": [
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientMount"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "elasticfilesystem:AccessedViaMountTarget": "true"
        }
      }
    },
    {
      "Sid": "DenyUnencryptedAccessForAll",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Key Change:** `"Principal": "*"` instead of specific account ARN.

---

## References

- [AWS EFS Resource-Based Policies](https://docs.aws.amazon.com/efs/latest/ug/efs-resource-based-policies.html)
- [AWS Policy Principal Element](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html)
- [Encrypting Data in Transit with EFS](https://docs.aws.amazon.com/efs/latest/ug/encryption-in-transit.html)
