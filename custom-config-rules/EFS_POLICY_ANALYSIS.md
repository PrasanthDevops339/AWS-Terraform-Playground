# EFS Policy Analysis - TLS Enforcement Gap

## Date: February 1, 2026

## Policy Under Review

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OnlyallowAccessViaMountTargetandpermitmountaccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::637423432759:root"
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
        "AWS": "arn:aws:iam::111111111111111:root"
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

## Current Lambda Compliance Result: ✅ COMPLIANT

The Lambda rule marked this policy as **COMPLIANT** because it found:
- ✅ `Effect: Deny` statement exists
- ✅ `Action: *` covers all actions (including EFS client actions)
- ✅ `aws:SecureTransport: false` condition present

---

## 🚨 CRITICAL GAP IDENTIFIED

### Problem: Principal Restriction in Deny Statement

The Deny statement has a **specific Principal**:
```json
"Principal": {
  "AWS": "arn:aws:iam::111111111111111:root"
}
```

**This means TLS enforcement ONLY applies to requests from account `111111111111111`.**

### Security Impact

| Scenario | TLS Enforced? | Why |
|----------|---------------|-----|
| Request from account `111111111111111` without TLS | ✅ DENIED | Matches Deny principal |
| Request from account `637423432759` without TLS | ❌ ALLOWED | Doesn't match Deny principal |
| Request from ANY OTHER account without TLS | ❌ ALLOWED | Doesn't match Deny principal |

**The EFS file system is NOT protected from unencrypted access by most principals!**

---

## What the Lambda Currently Validates

| Check | Status | Notes |
|-------|--------|-------|
| Policy exists | ✅ Validated | |
| Deny statement present | ✅ Validated | |
| `aws:SecureTransport: false` condition | ✅ Validated | |
| Deny applies to EFS client actions | ✅ Validated | Action: * covers all |
| **Principal is `*` (all principals)** | ❌ NOT VALIDATED | **GAP** |

---

## Missing Validation Cases

### 1. Principal Validation (HIGH PRIORITY)

**Current behavior:** Lambda accepts any Deny statement with SecureTransport=false, regardless of Principal.

**Missing check:** Verify that `Principal` is `*` or `{"AWS": "*"}` to ensure TLS is enforced for ALL requesters.

**Impact:** Policies with restricted principals appear compliant but don't actually enforce TLS universally.

### 2. Resource Validation (MEDIUM PRIORITY)

**Current behavior:** Lambda doesn't validate the `Resource` field.

**Missing check:** Verify that `Resource` covers the EFS file system (or is `*`).

**Impact:** A policy that denies TLS-less access to a different resource would appear compliant.

### 3. Multiple Deny Statements (LOW PRIORITY)

**Current behavior:** Lambda stops at first matching Deny statement.

**Missing check:** If multiple Deny statements exist, ensure at least one covers all principals.

---

## Recommended Policy Fix

### Option 1: Change Principal to Wildcard (Recommended)

```json
{
  "Sid": "DenyUnencryptedAccessAndUploads",
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

### Option 2: Use AWS Wildcard in Principal Object

```json
{
  "Sid": "DenyUnencryptedAccessAndUploads",
  "Effect": "Deny",
  "Principal": {
    "AWS": "*"
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

---

## Lambda Enhancement Recommendations

### Add Principal Validation

```python
def _validates_principal(statement: Dict[str, Any]) -> bool:
    """
    Check if Deny statement applies to all principals.
    
    Valid patterns:
    - Principal: "*"
    - Principal: {"AWS": "*"}
    
    Invalid (too restrictive):
    - Principal: {"AWS": "arn:aws:iam::123456789012:root"}
    - Principal: {"AWS": ["arn:aws:iam::123456789012:root"]}
    """
    principal = statement.get('Principal', {})
    
    # Check for wildcard principal
    if principal == '*':
        return True
    
    if isinstance(principal, dict):
        aws_principal = principal.get('AWS', '')
        if aws_principal == '*':
            return True
        # Could also accept a list containing '*'
        if isinstance(aws_principal, list) and '*' in aws_principal:
            return True
    
    return False
```

### Updated Compliance Logic

```python
# In is_secure_transport_enforced():

# Current checks
if not secure_transport_check:
    continue

if not _validates_client_actions(statement):
    continue

# NEW: Add principal validation
if not _validates_principal(statement):
    logger.warning(
        "Found Deny with SecureTransport=false but Principal is restricted"
    )
    continue

return True
```

---

## Test Cases to Add

| Test # | Scenario | Expected Result |
|--------|----------|-----------------|
| 9 | Deny + SecureTransport=false + Principal=* | COMPLIANT |
| 10 | Deny + SecureTransport=false + Principal={"AWS": "*"} | COMPLIANT |
| 11 | Deny + SecureTransport=false + Principal=specific-account | NON_COMPLIANT |
| 12 | Deny + SecureTransport=false + Principal=list-without-wildcard | NON_COMPLIANT |

---

## Summary

| Aspect | Current State | Recommended State |
|--------|---------------|-------------------|
| Policy Principal | `arn:aws:iam::111111111111111:root` | `*` |
| Lambda Principal Check | Not implemented | Validate Principal is `*` |
| True Compliance | ❌ FALSE POSITIVE | ✅ Accurate |

---

## Action Items

1. **Immediate:** Update EFS policy to use `Principal: "*"` in Deny statement
2. **Short-term:** Enhance Lambda to validate Principal field
3. **Testing:** Add test cases for Principal validation
4. **Documentation:** Update compliance requirements to specify Principal must be `*`

---

## References

- [AWS EFS Resource-Based Policies](https://docs.aws.amazon.com/efs/latest/ug/efs-resource-policies.html)
- [IAM Policy Elements: Principal](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html)
- [aws:SecureTransport Condition Key](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-securetransport)
