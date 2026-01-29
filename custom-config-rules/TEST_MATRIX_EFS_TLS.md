# EFS TLS Enforcement Lambda - Test Matrix

## Overview

This document provides a comprehensive matrix of all test scenarios for the EFS TLS Enforcement Lambda function (`scripts/efs-tls-enforcement/lambda_function.py`).

## Test Execution

```bash
cd scripts/efs-tls-enforcement
python3 test_lambda.py
```

## Test Matrix

| # | Test Name | Scenario Key | Expected Result | Policy Effect | SecureTransport Condition | Action Pattern | Why This Result |
|---|-----------|--------------|-----------------|---------------|---------------------------|----------------|-----------------|
| 1 | No Policy | `no_policy` | NON_COMPLIANT | N/A | N/A | N/A | No policy attached to EFS = no TLS enforcement |
| 2 | Deny + Action=* + SecureTransport=false | `compliant_deny` | COMPLIANT | Deny | `Bool: aws:SecureTransport = false` | `*` | Wildcard covers all actions including EFS client actions |
| 3 | Specific EFS Client Actions | `compliant_efs_actions` | COMPLIANT | Deny | `Bool: aws:SecureTransport = false` | `[ClientMount, ClientWrite, ClientRootAccess]` | Explicitly lists all required client actions |
| 4 | elasticfilesystem:* Wildcard | `compliant_efs_wildcard` | COMPLIANT | Deny | `Bool: aws:SecureTransport = false` | `elasticfilesystem:*` | EFS service wildcard covers all client actions |
| 5 | elasticfilesystem:Client* Pattern | `compliant_client_wildcard` | COMPLIANT | Deny | `Bool: aws:SecureTransport = false` | `elasticfilesystem:Client*` | Pattern matches ClientMount, ClientWrite, ClientRootAccess |
| 6 | BoolIfExists Condition | `compliant_bool_if_exists` | COMPLIANT | Deny | `BoolIfExists: aws:SecureTransport = false` | `*` | BoolIfExists handles missing key gracefully |
| 7 | No SecureTransport Enforcement | `non_compliant` | NON_COMPLIANT | Allow | None | `*` | Allow-only policy without TLS requirement |
| 8 | Wrong Actions | `non_compliant_wrong_action` | NON_COMPLIANT | Deny | `Bool: aws:SecureTransport = false` | `s3:GetObject` | Deny doesn't apply to EFS client actions |

## Detailed Test Scenarios

### Test 1: No Policy (`no_policy`)

**Scenario:** EFS file system has no resource policy attached.

**Mock Behavior:** Raises `PolicyNotFound` exception.

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `MockEFSClient.describe_file_system_policy()`

```python
if self.scenario == "no_policy":
    raise MockPolicyNotFoundException("Policy not found")
```

**Lambda Logic:** Catches `PolicyNotFound` exception → Returns NON_COMPLIANT

---

### Test 2: Compliant Deny with Wildcard Action (`compliant_deny`)

**Scenario:** Policy denies all actions when SecureTransport is false.

**Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedTransport",
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

**Why Compliant:** `Action: "*"` covers all actions, including EFS client actions.

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `compliant_deny` scenario

---

### Test 3: Specific EFS Client Actions (`compliant_efs_actions`)

**Scenario:** Policy explicitly denies specific EFS client actions when SecureTransport is false.

**Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedClientMount",
      "Effect": "Deny",
      "Principal": "*",
      "Action": [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ],
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

**Why Compliant:** Explicitly lists all three required EFS client actions.

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `compliant_efs_actions` scenario

---

### Test 4: EFS Service Wildcard (`compliant_efs_wildcard`)

**Scenario:** Policy uses `elasticfilesystem:*` to deny all EFS actions.

**Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedEFS",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "elasticfilesystem:*",
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

**Why Compliant:** `elasticfilesystem:*` matches all EFS actions including client actions.

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `compliant_efs_wildcard` scenario

---

### Test 5: Client Action Pattern (`compliant_client_wildcard`)

**Scenario:** Policy uses `elasticfilesystem:Client*` pattern to match client actions.

**Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedClient",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "elasticfilesystem:Client*",
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

**Why Compliant:** Pattern `elasticfilesystem:Client*` matches:
- `elasticfilesystem:ClientMount`
- `elasticfilesystem:ClientWrite`
- `elasticfilesystem:ClientRootAccess`

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `compliant_client_wildcard` scenario

---

### Test 6: BoolIfExists Condition (`compliant_bool_if_exists`)

**Scenario:** Policy uses `BoolIfExists` instead of `Bool` for condition.

**Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Why Compliant:** `BoolIfExists` is a valid alternative that handles cases where the `aws:SecureTransport` key might not exist in the request context.

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `compliant_bool_if_exists` scenario

---

### Test 7: No SecureTransport Enforcement (`non_compliant`)

**Scenario:** Policy only allows access without any TLS requirement.

**Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAll",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "*",
      "Resource": "*"
    }
  ]
}
```

**Why Non-Compliant:** No `Deny` statement with `aws:SecureTransport` condition. TLS is not enforced.

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `non_compliant` scenario

---

### Test 8: Wrong Actions (`non_compliant_wrong_action`)

**Scenario:** Policy has SecureTransport denial but for wrong (non-EFS) actions.

**Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyWrongAction",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
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

**Why Non-Compliant:** The `Deny` applies to `s3:GetObject`, not EFS client actions. This is a **mis-scoped policy** that appears to enforce TLS but doesn't actually protect EFS.

**Code Reference:** [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) - `non_compliant_wrong_action` scenario

---

## Lambda Function Validation Logic

### EFS Client Actions Checked

The Lambda function validates that Deny statements apply to these EFS client actions:

| Action | Description |
|--------|-------------|
| `elasticfilesystem:ClientMount` | Mount the EFS file system |
| `elasticfilesystem:ClientWrite` | Write data to the file system |
| `elasticfilesystem:ClientRootAccess` | Root access to the file system |

### Action Pattern Matching

The function accepts these action patterns as valid for client action coverage:

| Pattern | Matches Client Actions | Example |
|---------|----------------------|---------|
| `*` | ✅ Yes | All actions including EFS |
| `elasticfilesystem:*` | ✅ Yes | All EFS actions |
| `elasticfilesystem:Client*` | ✅ Yes | All client operations |
| `elasticfilesystem:ClientMount` | ✅ Yes (partial) | Only mount operations |
| `s3:*` | ❌ No | S3 actions, not EFS |
| `ec2:*` | ❌ No | EC2 actions, not EFS |

### Validation Flow

```
1. Check Effect == "Deny"
   └─ Skip if not Deny
   
2. Check Condition has SecureTransport=false
   ├─ Bool.aws:SecureTransport == "false"
   └─ BoolIfExists.aws:SecureTransport == "false"
   
3. Check Action covers EFS client actions
   ├─ Action == "*" → PASS
   ├─ Action == "elasticfilesystem:*" → PASS
   ├─ Action == "elasticfilesystem:Client*" → PASS
   ├─ Action list contains client actions → PASS
   └─ Action doesn't match client actions → FAIL
   
4. All checks pass → COMPLIANT
   Any check fails → Continue to next statement
   No valid statement found → NON_COMPLIANT
```

## Code References

| File | Purpose |
|------|---------|
| [lambda_function.py](scripts/efs-tls-enforcement/lambda_function.py) | Main Lambda function |
| [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py) | Test suite with mock scenarios |
| [LAMBDA_LOCAL_TESTING.md](LAMBDA_LOCAL_TESTING.md) | Local testing guide |
| [README_EFS_COMPLIANCE.md](README_EFS_COMPLIANCE.md) | Full compliance documentation |

## Key Functions in Lambda

| Function | Purpose |
|----------|---------|
| `lambda_handler()` | Main entry point, receives Config event |
| `evaluate_efs_tls_policy()` | Retrieves and evaluates EFS policy |
| `is_secure_transport_enforced()` | Validates SecureTransport + client actions |
| `_validates_client_actions()` | Checks if statement applies to EFS client actions |
| `_action_matches()` | Pattern matching for action strings |

## Adding New Test Scenarios

To add a new test scenario:

1. **Add scenario to MockEFSClient** in [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py):
```python
elif self.scenario == "your_new_scenario":
    return {
        'Policy': json.dumps({
            # Your policy JSON here
        })
    }
```

2. **Add test case to test_scenarios** in `main()`:
```python
{
    'name': 'Your Test Description',
    'scenario': 'your_new_scenario',
    'expected': 'COMPLIANT'  # or 'NON_COMPLIANT'
}
```

3. **Update this matrix** with the new test case.

---

## Version History

| Date | Changes |
|------|---------|
| 2026-01-29 | Initial test matrix with 8 scenarios |
