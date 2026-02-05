# EFS TLS Enforcement Lambda Rule

## Overview

This Lambda function validates that EFS file systems enforce TLS encryption in transit via resource policies with `aws:SecureTransport` condition.

## Why Lambda is Required

| Requirement | Guard Policy | Lambda |
|-------------|:------------:|:------:|
| Config item data | ✅ | ✅ |
| EFS resource policy | ❌ | ✅ |
| API calls (DescribeFileSystemPolicy) | ❌ | ✅ |
| JSON policy parsing | ❌ | ✅ |

EFS resource policies are **NOT** included in AWS Config configuration items. This Lambda calls the `efs:DescribeFileSystemPolicy` API to retrieve and evaluate the policy.

## Compliance Criteria

An EFS file system is **COMPLIANT** if its resource policy contains a **Deny** statement that:

1. Uses `Effect: Deny`
2. Has condition `Bool: { "aws:SecureTransport": "false" }` or `BoolIfExists`
3. Applies to EFS client actions:
   - `elasticfilesystem:ClientMount`
   - `elasticfilesystem:ClientWrite`
   - `elasticfilesystem:ClientRootAccess`

### Valid Action Patterns

- `*` (all actions)
- `elasticfilesystem:*` (all EFS actions)
- `elasticfilesystem:Client*` (all client actions)
- Explicit list containing the three client actions

## Possible Annotations

The Lambda function produces the following annotations based on evaluation results:

### COMPLIANT

| Annotation | Condition |
|------------|-----------|
| `EFS file system has a resource policy that enforces TLS (denies non-secure transport)` | Policy contains valid Deny statement with `aws:SecureTransport: false` condition covering required client actions |

### NON_COMPLIANT

| Annotation | Condition |
|------------|-----------|
| `EFS file system does not have a resource policy attached` | No resource policy exists on the EFS file system |
| `Resource policy is empty or invalid` | Policy exists but is empty or malformed |
| `Resource policy does not enforce TLS - no Deny statement with aws:SecureTransport condition found` | Policy exists but lacks the required Deny statement structure |
| `Resource policy has SecureTransport condition but does not cover required client actions` | Policy has SecureTransport condition but actions don't include `ClientMount`, `ClientWrite`, `ClientRootAccess` |
| `EFS file system not found or policy evaluation failed` | API call failed or file system doesn't exist |

### NOT_APPLICABLE

| Annotation | Condition |
|------------|-----------|
| `Resource was deleted or is not in scope` | Resource deleted during evaluation |
| `Configuration item type is not AWS::EFS::FileSystem` | Wrong resource type passed to the rule |
| `Unsupported configuration item status: <status>` | Config item has unsupported status (e.g., `ResourceNotRecorded`) |

## Example Compliant Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnforceTLS",
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

## Deployment

This Lambda is deployed via the `lambda_rule` module in the Lambda Rules Conformance Pack:

```hcl
module "lambda_rules_pack" {
  source = "../../modules/lambda_conformance_pack"
  
  cpack_name = "lambda-rules"
  
  lambda_rules_list = [
    {
      config_rule_name     = "efs-tls-enforcement"
      description          = "Validates EFS file systems enforce TLS via resource policy"
      lambda_script_dir    = "../../scripts/efs-tls-enforcement"
      resource_types_scope = ["AWS::EFS::FileSystem"]
      additional_policies  = [file("../../iam/efs-tls-enforcement.json")]
    }
  ]
}
```

## Local Testing

```bash
# Install test dependencies
pip install pytest boto3 moto

# Run tests
python -m pytest test_lambda.py -v
```

## Complements

- **efs-validation** (Guard policy): Validates EFS encryption-at-rest
- **efs-tls-enforcement** (Lambda): Validates EFS encryption-in-transit

Together, these rules ensure complete EFS encryption compliance.

## Files

| File | Purpose |
|------|---------|
| `lambda_function.py` | Main Lambda handler |
| `requirements.txt` | Python dependencies |
| `README.md` | This documentation |

## IAM Permissions Required

The Lambda requires additional IAM permissions to call EFS APIs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EFSDescribePolicy",
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeFileSystemPolicy",
        "elasticfilesystem:DescribeFileSystems"
      ],
      "Resource": "*"
    }
  ]
}
```

This policy is provided via `iam/efs-tls-enforcement.json`.
