# Simple EFS Deployment - Policy Present but Insufficient (Non-Compliant)

⚠️ **WARNING: This EFS has a resource policy but it does NOT properly enforce TLS for EFS client actions.**

This deployment is intentionally misconfigured to demonstrate a **NON-COMPLIANT** scenario for AWS Config rule testing.

## Purpose

This project tests the Config Lambda rule's ability to detect an **insufficient policy**. Unlike `simple-efs-unencrypted` which has no policy at all, this deployment has a policy with a `SecureTransport` condition that looks correct at first glance, but **fails to protect EFS client operations**.

## Why This Is Non-Compliant

The EFS file system policy contains:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": {"AWS": "*"},
      "Action": [
        "elasticfilesystem:DescribeFileSystem",
        "elasticfilesystem:DescribeAccessPoints"
      ],
      "Resource": "arn:aws:elasticfilesystem:...",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**The Problem:**
- ✅ Policy exists
- ✅ Has `SecureTransport` condition
- ❌ **Only denies `DescribeFileSystem` and `DescribeAccessPoints` actions**
- ❌ **Does NOT deny `ClientMount`, `ClientWrite`, or `ClientRootAccess`**
- ❌ **Clients can still mount without TLS!**

## Lambda Function Validation Logic

The Lambda function in `custom-config-rules/scripts/efs-tls-enforcement/lambda_function.py` validates:

1. ✅ Policy exists (passes this check)
2. ✅ Policy has `SecureTransport=false` Deny condition (passes this check)
3. ❌ **Deny applies to EFS client actions** (FAILS this check)

The function specifically checks that the Deny statement applies to:
- `elasticfilesystem:ClientMount`
- `elasticfilesystem:ClientWrite`
- `elasticfilesystem:ClientRootAccess`

Or wildcard patterns like:
- `*` (all actions)
- `elasticfilesystem:*` (all EFS actions)
- `elasticfilesystem:Client*` (all client actions)

Since this policy only denies **Describe** actions, not **Client** actions, the Lambda will correctly mark it as **NON_COMPLIANT**.

## Architecture

This deployment creates:

- **KMS Key**: Customer-managed KMS key for EFS encryption at rest
- **Security Group**: Controls network access to EFS mount targets (NFS port 2049)
- **EFS File System**: Encrypted-at-rest file system
- **EFS File System Policy**: ⚠️ **Insufficient policy** (does not enforce TLS for client actions)
- **Mount Targets**: Deployed across multiple subnets for high availability

## Comparison with Other Test Cases

| Project | Policy Exists? | SecureTransport Condition? | Applies to Client Actions? | Compliance |
|---------|---------------|---------------------------|---------------------------|-----------|
| `simple-efs-deployment` | ✅ Yes | ✅ Yes | ✅ Yes | **COMPLIANT** |
| `simple-efs-unencrypted` | ❌ No | ❌ No | ❌ No | **NON_COMPLIANT** (no policy) |
| `simple-efs-policy-insufficient` | ✅ Yes | ✅ Yes | ❌ No | **NON_COMPLIANT** (wrong actions) |

## Prerequisites

- Terraform >= 1.5.0
- AWS Provider >= 5.0.0
- Existing VPC with subnets
- AWS credentials configured

## Usage

### 1. Initialize and Deploy

```bash
cd projects/simple-efs-policy-insufficient

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 2. Verify Non-Compliance

After deployment, the AWS Config rule should evaluate this EFS as **NON_COMPLIANT** with the annotation:

```
EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)
```

### 3. Test Lambda Function

You can test the Lambda function locally:

```bash
cd ../../custom-config-rules/scripts/efs-tls-enforcement

# Run tests
python -m pytest test_lambda.py -v -k test_insufficient_policy
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `aws_region` | AWS region for deployment | `string` | `"us-east-2"` |
| `environment` | Environment name | `string` | `"dev"` |
| `project_name` | Name of the project | `string` | `"simple-efs-policy-insufficient"` |
| `vpc_name` | Name tag of the VPC | `string` | `"ins-dev-vpc-use2"` |
| `subnet_name_filter` | Filter pattern for subnets | `string` | `"*-data-*"` |
| `allowed_cidrs` | CIDR blocks allowed to access EFS | `list(string)` | `["10.0.0.0/16"]` |
| `enable_backup` | Enable EFS backup policy | `bool` | `true` |
| `tags` | Additional tags | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `efs_id` | The ID of the EFS file system |
| `efs_arn` | The ARN of the EFS file system |
| `efs_dns_name` | The DNS name for mounting |
| `policy_status` | Shows non-compliant status |
| `compliance_details` | Detailed breakdown of policy issues |

## Security Considerations

⚠️ **This is a deliberately misconfigured deployment for testing purposes.**

**Do NOT use this configuration in production!**

### Issues with this configuration:
1. Policy does not enforce TLS for client mount operations
2. Clients can mount the file system without encryption in transit
3. Data transmitted between clients and EFS is vulnerable to interception

### For production, use:
- `simple-efs-deployment` with proper TLS enforcement policy
- TLS mount options: `-o tls`
- Policy that denies `ClientMount`, `ClientWrite`, `ClientRootAccess` when `SecureTransport=false`

## How to Fix

To make this deployment compliant, replace the policy with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureClientAccess",
      "Effect": "Deny",
      "Principal": {"AWS": "*"},
      "Action": [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ],
      "Resource": "arn:aws:elasticfilesystem:...",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

Or simply use `elasticfilesystem:*` or `*` in the Action field.

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Related Files

- Lambda Function: `../../custom-config-rules/scripts/efs-tls-enforcement/lambda_function.py`
- Lambda Tests: `../../custom-config-rules/scripts/efs-tls-enforcement/test_lambda.py`
- Compliant Example: `../simple-efs-deployment/`
- No Policy Example: `../simple-efs-unencrypted/`
