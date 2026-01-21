# AFT Account Customizations - Deployment Guide

## 🎯 Overview

This AFT customization deploys **dual-layer compliance enforcement** to each account:
- **4 Lambda-based Config Rules** - Complex tag value validation
- **1 Conformance Pack** with 3 Guard policy rules - Encryption and basic validation

## ✅ Key Design Decision

**AFT runs Terraform IN EACH ACCOUNT**, so:
- ✅ We use **account-level** conformance packs (NOT organization packs)
- ✅ Each account gets its own Config rules deployed locally
- ✅ Simpler architecture, no cross-account dependencies
- ✅ AWS Config recorder must already exist (managed by Control Tower)

## 📦 What Gets Deployed

### Lambda-Based Config Rules (4 total)
1. **backup-tagging-enforcement** - Validates backup schedule tags (EC2, RDS, EBS)
2. **ebs-tagging-enforcement** - Validates EBS volume tags
3. **sqs-tagging-enforcement** - Validates SQS queue tags
4. **efs-tagging-enforcement** - Validates EFS file system tags

### Guard Policy Conformance Pack (3 rules)
1. **ebs-validation** - EBS encryption + tag presence
2. **sqs-validation** - SQS encryption + Environment tag values
3. **efs-validation** - EFS encryption + PerformanceMode + Environment tag values

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────┐
│           AFT Account Customization Phase              │
│         (Runs in EACH account individually)            │
├────────────────────────────────────────────────────────┤
│                                                        │
│  Terraform Execution in Account: 123456789012         │
│                                                        │
│  ┌──────────────────────┬─────────────────────────┐   │
│  │ Lambda Rules         │ Guard Policy Rules      │   │
│  │                      │                         │   │
│  │ ✅ backup_tags       │ ✅ ebs-validation        │   │
│  │ ✅ ebs_tags          │ ✅ sqs-validation        │   │
│  │ ✅ sqs_tags          │ ✅ efs-validation        │   │
│  │ ✅ efs_tags          │                         │   │
│  │                      │                         │   │
│  │ (4 Config Rules)     │ (1 Conformance Pack)    │   │
│  └──────────────────────┴─────────────────────────┘   │
│                                                        │
│  Uses existing AWS Config recorder ✓                  │
│  (Managed by Control Tower)                           │
└────────────────────────────────────────────────────────┘
```

## 🚀 Deployment Steps

### Prerequisites

1. **AWS Config must be enabled** in target accounts (Control Tower does this)
2. **AFT pipeline** must be configured
3. **IAM permissions** for AFT execution role to create Lambda functions and Config rules

### Deploy via AFT

1. **Update your AFT account request** to reference this customization:

```hcl
module "aft_account_request" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail              = "account@example.com"
    AccountName               = "prod-workload"
    ManagedOrganizationalUnit = "Production"
    SSOUserEmail              = "admin@example.com"
    SSOUserFirstName          = "Admin"
    SSOUserLastName           = "User"
  }

  account_customizations_name = "terraform-aft-account-customizations"
  
  account_tags = {
    Environment = "production"
  }
}
```

2. **AFT will automatically**:
   - Run Terraform in the new account
   - Deploy all 4 Lambda functions
   - Deploy the conformance pack with 3 Guard rules
   - Configure Config rules to monitor resources

3. **Verify deployment**:
```bash
# Check Config rules
aws configservice describe-config-rules

# Check conformance pack
aws configservice describe-conformance-packs

# Check Lambda functions
aws lambda list-functions | grep -E "backup_tags|ebs_tags|sqs_tags|efs_tags"
```

## ⚙️ Configuration

### Variables Required

In [variables.tf](variables.tf):

```terraform
variable "account_name" {
  type        = string
  description = "Account name/identifier"
}

variable "environment" {
  type    = string
  default = "prd"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key for Lambda log encryption"
}

variable "config_resource_types" {
  type    = list(string)
  default = ["AWS::EC2::Instance", "AWS::EC2::Volume", "AWS::RDS::DBInstance"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

### Customize Tag Requirements

**Lambda Rules** - Edit JSON files:
- [backup_tags.json](../modules/scripts/backup-tags/backup_tags.json)
- [ebs_tags.json](../modules/scripts/ebs-tags/ebs_tags.json)
- [sqs_tags.json](../modules/scripts/sqs-tags/sqs_tags.json)
- [efs_tags.json](../modules/scripts/efs-tags/efs_tags.json)

**Guard Rules** - Edit .guard files:
- [ebs-validation-2026-01-21.guard](../../policies/ebs-validation/ebs-validation-2026-01-21.guard)
- [sqs-validation-2026-01-21.guard](../../policies/sqs-validation/sqs-validation-2026-01-21.guard)
- [efs-validation-2026-01-21.guard](../../policies/efs-validation/efs-validation-2026-01-21.guard)

## 📊 Monitoring

### View Compliance in Each Account

**AWS Console** → Config → Dashboard

You'll see:
- **7 Config Rules** (4 Lambda + 3 from conformance pack)
- Compliance status per resource
- Non-compliant resources with annotations

### CloudWatch Logs

Lambda functions log to:
```
/aws/lambda/{account-alias}-{function-name}-function-{environment}
```

Example:
```
/aws/lambda/prod-workload-ebs_tags-function-prd
```

### Sample Compliance Results

**Compliant Resource:**
```
✅ EBS Volume vol-123456
   - All required tags present
   - Encrypted: true
   - Tags match approved values
```

**Non-Compliant Resource:**
```
❌ SQS Queue my-queue
   Lambda Rule: "Required SQS tag keys are missing: Owner, Application"
   Guard Rule: "SQS's must be encrypted"
```

## 🔧 Troubleshooting

### Config Rules Not Appearing

**Check:**
```bash
# Verify Config recorder is active
aws configservice describe-configuration-recorder-status

# Should show: "recording": true, "lastStatus": "SUCCESS"
```

**Fix:** Control Tower should manage this. If not, contact your AWS admin.

### Lambda Functions Failing

**Check CloudWatch Logs:**
```bash
aws logs tail /aws/lambda/{account-alias}-ebs_tags-function-prd --follow
```

**Common issues:**
- JSON file syntax errors
- IAM permission issues
- Python runtime errors

### Conformance Pack Failed

**Check status:**
```bash
aws configservice describe-conformance-pack-status \
  --conformance-pack-names {account-alias}-resource-validation
```

**Common issues:**
- Guard syntax errors in .guard files
- Config recorder not enabled
- Resource type not supported in region

### Guard Syntax Validation

**Test locally:**
```bash
# Install cfn-guard
cargo install cfn-guard

# Validate Guard files
cfn-guard validate -r policies/ebs-validation/ebs-validation-2026-01-21.guard
```

## 📋 Compliance Checklist

Before deploying:
- [ ] AWS Config enabled in target accounts
- [ ] AFT pipeline configured
- [ ] JSON tag configurations reviewed
- [ ] Guard policy files validated
- [ ] IAM permissions verified
- [ ] Test in sandbox account first

After deployment:
- [ ] Config rules appear in console
- [ ] Conformance pack status is ACTIVE
- [ ] Lambda functions exist and are invocable by Config
- [ ] CloudWatch logs show evaluations
- [ ] Test resources trigger compliance checks

## 🔄 Updating Rules

### Update Lambda Rule Logic

1. Edit Python file in `modules/scripts/{rule-name}/`
2. Commit changes
3. AFT will redeploy on next account update

### Update Guard Policies

1. Create new version:
```bash
cp policies/ebs-validation/ebs-validation-2026-01-21.guard \
   policies/ebs-validation/ebs-validation-2026-02-01.guard
```

2. Update reference in [tagging-enforcement.tf](tagging-enforcement.tf)

3. Commit and let AFT redeploy

## 🎯 Best Practices

1. **Test in Dev First** - Deploy to dev accounts before production
2. **Version Guard Files** - Use dated versions for rollback capability
3. **Monitor Deployment** - Watch AFT pipeline logs
4. **Review Compliance** - Check Config dashboard after deployment
5. **Document Exceptions** - Use excluded_accounts if needed
6. **Regular Updates** - Review and update tag requirements quarterly

## 📚 Related Documentation

- [Lambda Rules Guide](../../IMPLEMENTATION_GUIDE.md)
- [Guard Policies Guide](../../GUARD_POLICIES_GUIDE.md)
- [AFT Documentation](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)
- [AWS Config Guide](https://docs.aws.amazon.com/config/latest/developerguide/WhatIsConfig.html)

## 🆘 Support

Issues? Check:
1. CloudWatch logs for Lambda errors
2. Config rule evaluation history
3. Conformance pack status
4. AFT pipeline logs in management account

---

**Ready to Deploy!** 🚀

Copy `FINAL-tagging-enforcement.tf` to `tagging-enforcement.tf` and commit to AFT repository.
