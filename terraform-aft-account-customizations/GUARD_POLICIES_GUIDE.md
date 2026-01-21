# Guard Policy Rules for AFT Account Customizations

## 📋 Overview

This directory contains **AWS Config Guard policies** that complement the Lambda-based custom rules. These policy-as-code rules provide declarative validation for resource configuration and compliance.

## 🎯 Guard Rules vs Lambda Rules

### **Lambda-Based Custom Rules** (existing)
- ✅ Custom validation logic in Python
- ✅ Read from JSON configuration files
- ✅ Good for complex business logic
- ✅ Tag value validation against approved lists

### **Guard Policy Rules** (new)
- ✅ Declarative policy-as-code (no programming needed)
- ✅ Fast evaluation using AWS Config managed runtime
- ✅ Good for simple checks (encryption, tags presence, etc.)
- ✅ Version controlled and easy to audit

## 📦 Implemented Guard Policies

### 1. **EBS Validation** ([ebs-validation-2026-01-21.guard](policies/ebs-validation/ebs-validation-2026-01-21.guard))

**Validates:**
- ✅ EBS volumes are encrypted
- ✅ EBS snapshots are encrypted
- ✅ Required tags are present

**Rules:**
- `ebsIsEncrypted` - Volume encryption check
- `ebsSnapshotIsEncrypted` - Snapshot encryption check
- `ebsHasRequiredTags` - Tags: ops:backupschedule1/2/3, Environment, Owner

### 2. **SQS Validation** ([sqs-validation-2026-01-21.guard](policies/sqs-validation/sqs-validation-2026-01-21.guard))

**Validates:**
- ✅ SQS queues have SSE enabled
- ✅ Required tags are present
- ✅ Environment tag has valid values

**Rules:**
- `sqsIsEncrypted` - SSE encryption check
- `sqsHasRequiredTags` - Tags: Environment, Owner, Application, CostCenter
- `sqsHasValidEnvironmentTag` - Environment: dev/staging/production/test

### 3. **EFS Validation** ([efs-validation-2026-01-21.guard](policies/efs-validation/efs-validation-2026-01-21.guard))

**Validates:**
- ✅ EFS file systems are encrypted
- ✅ Performance mode is valid
- ✅ Required tags are present
- ✅ Environment tag has valid values

**Rules:**
- `efsIsEncrypted` - Encryption at rest check
- `efsHasRequiredTags` - Tags: ops:backupschedule1/2, Environment, Owner, Application
- `efsHasValidPerformanceMode` - generalPurpose or maxIO
- `efsHasValidEnvironmentTag` - Environment: dev/staging/production/test

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│         AFT Account Customizations Framework               │
├─────────────────────┬───────────────────────────────────────┤
│                     │                                       │
│  Lambda Rules       │  Guard Policy Rules                   │
│  (Custom Logic)     │  (Policy-as-Code)                     │
│                     │                                       │
│  ┌─────────────┐    │  ┌─────────────────────────────────┐ │
│  │ backup_tags │    │  │  Conformance Pack               │ │
│  │ ebs_tags    │    │  │  ├─ ebs-validation (Guard)     │ │
│  │ sqs_tags    │    │  │  ├─ sqs-validation (Guard)     │ │
│  │ efs_tags    │    │  │  └─ efs-validation (Guard)     │ │
│  └─────────────┘    │  └─────────────────────────────────┘ │
│         ↓           │                ↓                      │
│  ┌─────────────┐    │  ┌─────────────────────────────────┐ │
│  │ Config      │    │  │ AWS Config Policy Runtime       │ │
│  │ Rules       │    │  │ (Managed Service)               │ │
│  └─────────────┘    │  └─────────────────────────────────┘ │
└─────────────────────┴───────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│            AWS Config Compliance Dashboard                  │
│  - Lambda Custom Rules                                      │
│  - Guard Policy Rules (via Conformance Pack)                │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
terraform-aft-account-customizations/
├── exceptions/terraform/
│   └── tagging-enforcement.tf       # Wires up both Lambda + Guard rules
├── modules/
│   ├── lambda/                      # Lambda-based custom rules
│   ├── conformance_pack/            # Guard policy module (NEW)
│   │   ├── cpack_account.tf        # Account-level pack
│   │   ├── cpack_organization.tf   # Org-level pack
│   │   ├── locals.tf               # Template generation logic
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── data.tf
│   │   └── templates/
│   │       └── guard_template.yml  # Config rule YAML template
│   └── scripts/                     # Lambda function code
└── policies/                        # Guard policy files (NEW)
    ├── ebs-validation/
    │   └── ebs-validation-2026-01-21.guard
    ├── sqs-validation/
    │   └── sqs-validation-2026-01-21.guard
    └── efs-validation/
        └── efs-validation-2026-01-21.guard
```

## 🚀 Deployment

### Option 1: Account-Level Deployment

```bash
cd exceptions/terraform

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply
```

This deploys:
- 4 Lambda-based custom rules (backup, EBS, SQS, EFS tag validation)
- 1 Conformance pack with 3 Guard policy rules (EBS, SQS, EFS validation)

### Option 2: Organization-Level Deployment

Edit [tagging-enforcement.tf](exceptions/terraform/tagging-enforcement.tf):

```terraform
module "policy_rules_conformance_pack" {
  source = "../../modules/conformance_pack"

  cpack_name        = "resource-validation-pack"
  organization_pack = true  # Changed from false
  
  excluded_accounts = [
    "111111111111",  # Test account
    "222222222222"   # Sandbox account
  ]
  
  policy_rules_list = [
    # ... rules config
  ]
}
```

## ⚙️ Configuration

### Add New Guard Policy

1. **Create Guard file**:
```bash
mkdir -p policies/rds-validation
cat > policies/rds-validation/rds-validation-2026-01-21.guard << 'EOF'
rule rdsIsEncrypted when resourceType == "AWS::RDS::DBInstance" {
    configuration.StorageEncrypted == true <<RDS instances must be encrypted>>
}
EOF
```

2. **Update Terraform config**:
```terraform
module "policy_rules_conformance_pack" {
  # ... existing config
  
  policy_rules_list = [
    # ... existing rules
    {
      config_rule_name     = "rds-validation"
      config_rule_version  = "2026-01-21"
      description          = "Validates RDS encryption"
      resource_types_scope = ["AWS::RDS::DBInstance"]
    }
  ]
}
```

3. **Apply changes**:
```bash
terraform apply
```

### Update Existing Guard Policy

1. **Create new version**:
```bash
cp policies/ebs-validation/ebs-validation-2026-01-21.guard \
   policies/ebs-validation/ebs-validation-2026-02-01.guard
```

2. **Edit the new file** with your changes

3. **Update version reference** in Terraform:
```terraform
{
  config_rule_name     = "ebs-validation"
  config_rule_version  = "2026-02-01"  # Updated version
  description          = "Validates EBS encryption and required tags"
  resource_types_scope = ["AWS::EC2::Volume", "AWS::EC2::Snapshot"]
}
```

4. **Apply changes**:
```bash
terraform apply
```

## 📝 Guard Policy Syntax Examples

### Basic Encryption Check
```guard
rule s3IsEncrypted when resourceType == "AWS::S3::Bucket" {
    configuration.ServerSideEncryptionConfiguration exists
    <<S3 buckets must have encryption enabled>>
}
```

### Tag Validation
```guard
rule hasEnvironmentTag when resourceType == "AWS::EC2::Instance" {
    configuration.tags[*].key contains "Environment"
    <<EC2 instances must have Environment tag>>
}
```

### Value Validation
```guard
rule validInstanceType when resourceType == "AWS::EC2::Instance" {
    let approved_types = ["t3.micro", "t3.small", "t3.medium"]
    configuration.instanceType in %approved_types
    <<EC2 instances must use approved instance types>>
}
```

### Complex Validation
```guard
rule publicAccessBlocked when resourceType == "AWS::S3::Bucket" {
    configuration.PublicAccessBlockConfiguration exists
    configuration.PublicAccessBlockConfiguration.BlockPublicAcls == true
    configuration.PublicAccessBlockConfiguration.BlockPublicPolicy == true
    <<S3 buckets must block public access>>
}
```

## 🎯 When to Use Guard vs Lambda

| Use Case | Guard Policy | Lambda Custom Rule |
|----------|--------------|-------------------|
| Simple checks (encryption, tags exist) | ✅ Preferred | ❌ Overkill |
| Complex business logic | ❌ Limited | ✅ Preferred |
| Tag value validation against lists | ⚠️ Possible | ✅ Easier |
| Cross-resource validation | ❌ Not supported | ✅ Supported |
| Fast evaluation needed | ✅ Faster | ⚠️ Cold starts |
| Easy to maintain | ✅ Declarative | ⚠️ Code required |

## 📊 Monitoring

### View Conformance Pack Status

```bash
# List conformance packs
aws configservice describe-conformance-packs

# Get compliance summary
aws configservice get-conformance-pack-compliance-summary \
  --conformance-pack-name <pack-name>

# Describe pack status
aws configservice describe-conformance-pack-status \
  --conformance-pack-names <pack-name>
```

### CloudWatch Metrics

AWS Config publishes metrics for:
- `NonCompliantResources` - Count of non-compliant resources
- `ConformancePackCompliance` - Overall compliance percentage

### Compliance Dashboard

**AWS Console** → Config → Conformance Packs
- View overall compliance score
- Drill down by rule
- See non-compliant resources
- View evaluation history

## 🔧 Troubleshooting

### Pack Deployment Failed

**Error**: "Conformance pack failed to deploy"

**Solution**:
1. Verify AWS Config is enabled:
```bash
aws configservice describe-configuration-recorders
aws configservice describe-configuration-recorder-status
```

2. Check IAM permissions for Config service role

3. Validate Guard syntax:
```bash
cfn-guard validate -r policies/ebs-validation/*.guard
```

### Rule Not Evaluating

**Check**:
1. Resource type is in scope
2. Config recorder is recording the resource type
3. Guard syntax is valid
4. Policy runtime version is correct (`guard-2.x.x`)

### Syntax Errors in Guard Files

**Test locally**:
```bash
# Install cfn-guard
cargo install cfn-guard

# Validate syntax
cfn-guard validate -r policies/ebs-validation/ebs-validation-2026-01-21.guard
```

## 🔒 Security Best Practices

1. **Version Control** - Keep all `.guard` files in Git
2. **Code Review** - Review policy changes before deployment
3. **Testing** - Test policies in dev before production
4. **Least Privilege** - Config service role has minimal permissions
5. **Encryption** - S3 bucket for Config has versioning + encryption

## 📚 Resources

- [AWS Config Guard Documentation](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules_cfn-guard.html)
- [Guard GitHub Repository](https://github.com/aws-cloudformation/cloudformation-guard)
- [Conformance Pack Documentation](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html)
- [Guard Policy Examples](https://github.com/aws-cloudformation/cloudformation-guard/tree/main/guard/resources)

---

**Maintainer**: Cloud Operations Team  
**Last Updated**: January 21, 2026
