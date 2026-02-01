# EFS Encryption and TLS Enforcement - AWS Config Rules

## Overview

This implementation provides comprehensive AWS Config compliance checking for Amazon EFS file systems across your AWS Organization:

1. **EFS Encryption at Rest** - Guard policy rule (custom policy)
2. **EFS TLS Enforcement** - Custom Lambda rule (validates file system policies require `aws:SecureTransport`)

All rules are deployed organization-wide via **AWS Config Organization Conformance Packs**.

## EFS Compliance Rules Matrix

| Rule Name | Type | Purpose | Validates | Location | Version | Deployment |
|-----------|------|---------|-----------|----------|---------|------------|
| **efs-is-encrypted** | Guard Policy Rule | Encryption At-Rest | `configuration.Encrypted == true` | `policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard` | `2025-10-30` | Conformance Pack |
| **efs-tls-enforcement** | Custom Lambda Rule | Encryption In-Transit | `aws:SecureTransport` in resource policy | `scripts/efs-tls-enforcement/lambda_function.py` | Current | Conformance Pack + Standalone |

### Rule Details

| Aspect | Guard Policy (At-Rest) | Lambda Rule (In-Transit) |
|--------|------------------------|--------------------------|
| **What it checks** | EFS file system has encryption enabled | EFS resource policy enforces TLS for client actions |
| **Resource type** | `AWS::EFS::FileSystem` | `AWS::EFS::FileSystem` |
| **Technology** | AWS Config Guard DSL | Python 3.12 Lambda |
| **Trigger** | Configuration changes | Configuration changes |
| **Evaluation** | Guard engine evaluates policy | Lambda calls `efs:DescribeFileSystemPolicy` API |
| **Compliant when** | `Encrypted == true` | Policy has `Deny` with `SecureTransport == false` for EFS client actions |
| **Non-compliant when** | `Encrypted == false` or missing | No policy, missing TLS requirement, or Deny doesn't apply to client actions |
| **Region deployment** | us-east-2, us-east-1 | us-east-2, us-east-1 |
| **Maintenance** | Policy file updates only | Lambda code + IAM policy updates |
| **Dependencies** | None | Lambda function, IAM role, S3 bootstrap bucket |

### Why Two Separate Rules?

- **At-Rest Encryption**: Validates the EFS file system configuration itself (enabled/disabled)
- **In-Transit Encryption**: Validates the resource-based policy attached to EFS (TLS enforcement)

Both are required for complete EFS security compliance.

## Architecture

```
Organization Conformance Pack
├── Guard Policy Rules
│   └── efs-is-encrypted (Custom Policy - validates encryption at-rest)
└── Lambda Custom Rules
    └── efs-tls-enforcement (Custom Lambda - validates TLS in-transit)
        ├── Lambda Function
        ├── Lambda Execution Role
        └── Config Rule
```

## Components

### 1. Guard Policy Rule: EFS Encryption At-Rest

**File:** `policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard`  
**Version:** `2025-10-30` (referenced in `environments/prd/cpack_encryption.tf`)  
**Scope:** Encryption at-rest validation

Validates that EFS file systems have encryption enabled at rest.

```guard
rule efsIsEncrypted when resourceType == "AWS::EFS::FileSystem" {
    configuration.Encrypted == true <<EFS's must be encrypted>>
}
```

**Why Guard Policy Instead of AWS Managed Rule?**  
The Guard policy rule provides the same encryption-at-rest validation as the AWS managed rule `EFS_ENCRYPTED_CHECK`, but with these advantages:
- Full control over policy logic and versioning
- No dependency on AWS managed rule availability
- Consistent policy-as-code approach across all rules
- Version tracked in Git (`policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard`)

### 2. Custom Lambda Rule: EFS TLS Enforcement (In-Transit)

**Files:**
- `scripts/efs-tls-enforcement/lambda_function.py` - Lambda function code
- `scripts/efs-tls-enforcement/test_lambda.py` - Local test suite (8 test scenarios)
- `iam/efs-tls-enforcement.json` - IAM policy for Lambda  
**Scope:** Encryption in-transit validation (TLS enforcement)

**Functionality:**
- Triggered on EFS file system configuration changes
- Calls `efs:DescribeFileSystemPolicy` (boto3 service name is `efs`, not `elasticfilesystem`)
- Validates that the file system policy enforces TLS by checking for:
  - Deny statement with `aws:SecureTransport == false`
  - Deny applies to EFS client actions: `ClientMount`, `ClientWrite`, `ClientRootAccess`
  - Proper policy structure requiring encrypted transport
- Returns compliance status to AWS Config

**EFS Client Actions Validated:**
- `elasticfilesystem:ClientMount` - Mount operations
- `elasticfilesystem:ClientWrite` - Write operations
- `elasticfilesystem:ClientRootAccess` - Root access operations

**Accepted Action Patterns:**
- `*` (all actions)
- `elasticfilesystem:*` (all EFS actions)
- `elasticfilesystem:Client*` (all client actions)
- Explicit list of client actions

**Compliance Logic:**
- ✅ **COMPLIANT**: Policy exists, enforces `aws:SecureTransport`, and applies to EFS client actions
- ❌ **NON_COMPLIANT**: No policy, policy doesn't enforce TLS, or Deny applies to wrong actions
- ⚠️ **NOT_APPLICABLE**: Resource deleted

**Local Testing:**
The Lambda function supports local testing without AWS credentials. See [LAMBDA_LOCAL_TESTING.md](LAMBDA_LOCAL_TESTING.md) for details.

## Deployment

### Prerequisites

1. AWS Config enabled in target accounts/regions
2. AWS Organizations with delegated administrator for Config
3. Terraform >= 1.0
4. S3 bootstrap bucket for Lambda code (`<account-alias>-bootstrap-use2`)

### Directory Structure

```
custom-config-rules/
├── environments/
│   └── prd/
│       ├── cpack_encryption.tf       # Conformance pack configuration
│       ├── lambda_efs_tls.tf         # Lambda rule deployment
│       ├── data.tf
│       ├── main.tf
│       ├── variables.tf
│       └── versions.tf
├── modules/
│   ├── conformance_pack/
│   │   ├── cpack_organization.tf
│   │   ├── cpack_template.tf         # Multi-rule template generator
│   │   ├── variables.tf              # Support for Guard, Lambda, Managed rules
│   │   └── templates/
│   │       ├── guard_template.yml
│   │       ├── lambda_template.yml
│   │       └── managed_template.yml
│   └── lambda_rule/
│       ├── lambda.tf
│       ├── rule_organization.tf
│       ├── outputs.tf
│       └── iam/
│           └── lambda_policy.json
├── scripts/
│   └── efs-tls-enforcement/
│       ├── lambda_function.py         # Lambda function code
│       └── requirements.txt
├── iam/
│   └── efs-tls-enforcement.json       # Additional IAM permissions
└── policies/
    └── efs-is-encrypted/
        └── efs-is-encrypted-2025-10-30.guard
```

### Step-by-Step Deployment

#### 1. Initialize Terraform

```bash
cd environments/prd
terraform init
```

#### 2. Plan the Deployment

```bash
terraform plan
```

This will create:
- 2 Lambda functions (us-east-2, us-east-1)
- 2 Lambda execution roles with least privilege
- 2 AWS Config organization custom rules
- 2 Organization Conformance Packs containing:
  - Guard policy rule for EFS encryption
  - AWS managed rule for EFS encryption
  - Lambda custom rule for TLS enforcement

#### 3. Apply the Configuration

```bash
terraform apply
```

#### 4. Verify Deployment

```bash
# Check conformance pack status
aws configservice describe-organization-conformance-pack-statuses \
  --organization-conformance-pack-names <account-alias>-encryption-validation

# Check Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `efs-tls-enforcement`)].FunctionName'

# Check Config rules
aws configservice describe-organization-config-rules \
  --organization-config-rule-names efs-tls-enforcement
```

## Configuration

### Excluding Accounts

To exclude specific accounts from the conformance pack:

```hcl
module "cpack_encryption" {
  source            = "../../modules/conformance_pack"
  cpack_name        = "encryption-validation"
  organization_pack = true
  
  excluded_accounts = [
    "123456789012",  # dev-test-account
    "234567890123"   # sandbox-account
  ]
  
  # ... rest of configuration
}
```

### Multi-Region Deployment

The production configuration deploys to both `us-east-2` and `us-east-1`:

**Production (Organization-wide):**
```hcl
# Primary region (us-east-2)
module "efs_tls_enforcement" {
  source            = "../../modules/lambda_rule"
  organization_rule = true  # Organization-wide deployment
  # ...
}

# Secondary region (us-east-1)
module "efs_tls_enforcement_use1" {
  source = "../../modules/lambda_rule"
  organization_rule = true  # Organization-wide deployment
  providers = {
    aws = aws.use1
  }
  # ...
}
```

**Development (Single Account):**
```hcl
# Single account for testing
module "efs_tls_enforcement_dev" {
  source            = "../../modules/lambda_rule"
  organization_rule = false  # Single account only
  # ...
}
```

### Adding Additional Rules

To add more rules to the conformance pack:

```hcl
module "cpack_encryption" {
  # ... existing config
  
  # Add Guard policy rules
  policy_rules_list = [
    # ... existing rules
    {
      config_rule_name     = "new-guard-rule"
      config_rule_version  = "2026-01-26"
      description          = "Description of the rule"
      resource_types_scope = ["AWS::Resource::Type"]
    }
  ]
  
  # Add AWS managed rules
  managed_rules_list = [
    # ... existing rules
    {
      config_rule_name     = "new-managed-rule"
      description          = "Description"
      source_identifier    = "AWS_MANAGED_RULE_IDENTIFIER"
      resource_types_scope = ["AWS::Resource::Type"]
      input_parameters     = {
        paramKey = "paramValue"
      }
    }
  ]
  
  # Add Lambda custom rules
  lambda_rules_list = [
    # ... existing rules
    {
      config_rule_name     = "new-lambda-rule"
      description          = "Description"
      lambda_function_arn  = module.new_lambda.lambda_arn
      resource_types_scope = ["AWS::Resource::Type"]
      message_type         = "ConfigurationItemChangeNotification"
    }
  ]
}
```

## Lambda Function Details

### IAM Permissions

The Lambda execution role has the following permissions:

**Base permissions** (`modules/lambda_rule/iam/lambda_policy.json`):
- `logs:CreateLogGroup`
- `logs:CreateLogStream`
- `logs:PutLogEvents`
- `logs:DescribeLogStreams`
- `config:PutEvaluations`

**EFS-specific permissions** (`iam/efs-tls-enforcement.json`):
- `elasticfilesystem:DescribeFileSystemPolicy`
- `elasticfilesystem:DescribeFileSystems`

### Lambda Logic Flow

```python
1. Receive Config evaluation event
   ├─ Support both 'invokingEvent' and 'configRuleInvokingEvent' keys
   ├─ Log event keys (not full payload for security)
   └─ Top-level try/catch for graceful error handling
2. Validate configuration item
   ├─ Missing config item → NOT_APPLICABLE
   ├─ Missing resource ID → NOT_APPLICABLE
   └─ Non-target resource type → NOT_APPLICABLE
3. Parse OrderingTimestamp
   └─ Convert to datetime object (SDK requirement)
4. Handle deleted resources → NOT_APPLICABLE
5. Extract EFS file system ID
6. Call efs:DescribeFileSystemPolicy (lazy client initialization)
   ├─ PolicyNotFound → NON_COMPLIANT
   ├─ Parse policy JSON
   └─ Check for aws:SecureTransport enforcement
       ├─ Find Deny with SecureTransport=false
       │   └─ Validate Deny applies to EFS client actions
       │       ├─ Action: * → COMPLIANT
       │       ├─ Action: elasticfilesystem:* → COMPLIANT
       │       ├─ Action: elasticfilesystem:Client* → COMPLIANT
       │       ├─ Action includes ClientMount/Write/RootAccess → COMPLIANT
       │       └─ Action doesn't cover client actions → NON_COMPLIANT
       └─ No valid enforcement → NON_COMPLIANT
7. Clip annotation to 256 chars (AWS Config limit)
8. Submit evaluation to Config with PutEvaluations
```

### Robustness Features

The Lambda function includes defensive coding patterns:

| Feature | Description |
|---------|-------------|
| **Dual event key support** | Accepts both `invokingEvent` and `configRuleInvokingEvent` |
| **Top-level exception handling** | Prevents silent failures, logs and re-raises |
| **Safe timestamp parsing** | Converts to datetime with fallback to current time |
| **Graceful missing data handling** | Returns NOT_APPLICABLE for missing config items |
| **Annotation clipping** | Truncates long messages to 256 char AWS limit |
| **Reduced log verbosity** | Logs event keys, not full payload |
| **Centralized evaluation submission** | Helper functions for consistent responses |

### Local Testing

The Lambda function can be tested locally without AWS credentials:

```bash
cd scripts/efs-tls-enforcement
python3 test_lambda.py
```

**Test Scenarios (8 total):**
1. No Policy → NON_COMPLIANT
2. Deny + Action=* + SecureTransport=false → COMPLIANT
3. Deny + Specific EFS client actions → COMPLIANT
4. Deny + elasticfilesystem:* → COMPLIANT
5. Deny + elasticfilesystem:Client* → COMPLIANT
6. Deny + BoolIfExists condition → COMPLIANT
7. Allow without SecureTransport → NON_COMPLIANT
8. Deny + SecureTransport=false but wrong actions (e.g., s3:GetObject) → NON_COMPLIANT

See [LAMBDA_LOCAL_TESTING.md](LAMBDA_LOCAL_TESTING.md) for detailed testing guide.

## Compliance Validation

### Example Compliant EFS Policy

**Option 1: Wildcard action (simplest)**
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

**Option 2: EFS-specific wildcard**
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

**Option 3: Explicit client actions (most restrictive)**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedClientAccess",
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

### Checking Compliance

```bash
# Get conformance pack compliance
aws configservice describe-conformance-pack-compliance \
  --conformance-pack-name <account-alias>-encryption-validation

# Get specific rule compliance
aws configservice describe-compliance-by-config-rule \
  --config-rule-names <account-alias>-efs-tls-enforcement

# Get resource compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem
```

## Troubleshooting

### Lambda Function Issues

**Check Lambda logs:**
```bash
aws logs tail /aws/lambda/efs-tls-enforcement --follow
```

**Common issues:**
1. **Permission denied**: Verify IAM role has EFS describe permissions
2. **Timeout**: Increase Lambda timeout in `modules/lambda_rule/lambda.tf`
3. **PolicyNotFoundException**: This is expected for EFS without policies (returns NON_COMPLIANT)

### Conformance Pack Issues

**Check pack status:**
```bash
aws configservice describe-organization-conformance-pack-statuses
```

**Common issues:**
1. **CREATE_FAILED**: Check CloudFormation stack events in delegated admin account
2. **Lambda ARN not found**: Ensure Lambda is deployed before conformance pack
3. **Excluded accounts error**: Verify account IDs are correct

### Config Rule Issues

**Check rule status:**
```bash
aws configservice describe-config-rules \
  --config-rule-names <rule-name>
```

**Re-evaluate resources:**
```bash
aws configservice start-config-rules-evaluation \
  --config-rule-names <rule-name>
```

## Best Practices

1. **Version Control**: Always use versioned Guard policies (e.g., `2026-01-26`)
2. **Testing**: Test Lambda functions in dev/staging before production
3. **Monitoring**: Set up CloudWatch alarms for Lambda errors
4. **Documentation**: Document any custom rules and their compliance criteria
5. **Least Privilege**: Only grant necessary IAM permissions
6. **Multi-Region**: Deploy critical rules to multiple regions for redundancy
7. **Excluded Accounts**: Document why accounts are excluded from packs

## Cost Considerations

- **AWS Config**: Charged per configuration item recorded and per rule evaluation
- **Lambda**: Typically falls within free tier for Config evaluations
- **S3**: Minimal cost for Lambda code storage
- **CloudWatch Logs**: Lambda execution logs (can be set to expire)

**Estimated monthly cost** (for organization with 100 accounts):
- Config Rules: ~$2 per rule per region per account = $600/month (3 rules × 2 regions × 100 accounts)
- Lambda: Typically < $1/month
- S3/CloudWatch: < $5/month

## Maintenance

### Updating Lambda Function

1. Modify `scripts/efs-tls-enforcement/lambda_function.py`
2. Run `terraform apply`
3. Lambda code is automatically uploaded to S3 and function is updated

### Updating Guard Policies

1. Create new versioned policy file (e.g., `efs-is-encrypted-2026-02-01.guard`)
2. Update `config_rule_version` in conformance pack configuration
3. Run `terraform apply`

### Updating Conformance Pack

Terraform will automatically detect changes and update the conformance pack. Note: Updates may cause temporary evaluation pauses.

## Security Considerations

1. **Lambda Execution Role**: Uses least privilege IAM permissions
2. **Config Service Role**: Ensure AWS Config has proper service role
3. **S3 Bucket**: Lambda code bucket should have encryption and versioning enabled
4. **Secrets**: Never hardcode credentials in Lambda functions
5. **VPC**: Lambda functions run outside VPC by default (no VPC access needed)

## Support and Contributions

For issues, questions, or contributions:
1. Check CloudWatch Logs for Lambda errors
2. Review Terraform plan output before applying
3. Test changes in dev environment first
4. Document any customizations

## References

- [AWS Config Rules](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config.html)
- [AWS Config Conformance Packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html)
- [EFS Encryption](https://docs.aws.amazon.com/efs/latest/ug/encryption.html)
- [Guard Policy Language](https://docs.aws.amazon.com/cfn-guard/latest/ug/what-is-guard.html)
- [Lambda Config Rules](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules_lambda-functions.html)

## Version History

- **2026-01-29**: Enhanced Lambda to validate Deny applies to EFS client actions (ClientMount/ClientWrite/ClientRootAccess), fixed boto3 service name to 'efs', added lazy client initialization for local testing, 8 test scenarios
- **2026-01-26**: Initial implementation with Guard, Managed, and Lambda rules
- **2025-10-30**: Original EFS encryption Guard policy
- **2026-01-09**: Updated EBS encryption policy to 2026-01-09
