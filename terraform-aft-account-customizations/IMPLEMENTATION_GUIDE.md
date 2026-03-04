# Custom Config Rules Implementation Guide

## 📋 Overview

This repository now includes AWS Config custom rules for enforcing tag compliance across multiple AWS resource types using Lambda-based validation.

## 🎯 Implemented Rules

### 1. **Backup Schedule Tags** (EC2, RDS)
- **Rule Name**: `backup-tagging-enforcement`
- **Resources**: EC2 Instances, EBS Volumes, RDS Instances
- **Required Tags**:
  - `ops:backupschedule1`
  - `ops:backupschedule2`
  - `ops:backupschedule3`
- **Allowed Values**: none, hourly1day, hourly8day, 1xday14day, 1xday30day, 1xweek60day, 1xweek120day, 1xmonth365day

### 2. **EBS Volume Tags**
- **Rule Name**: `ebs-tagging-enforcement`
- **Resources**: EBS Volumes
- **Required Tags**:
  - `ops:backupschedule1`, `ops:backupschedule2`, `ops:backupschedule3` (same schedule values)
  - `Environment`: dev, staging, production, test
  - `Owner`: (any value)

### 3. **SQS Queue Tags**
- **Rule Name**: `sqs-tagging-enforcement`
- **Resources**: SQS Queues
- **Required Tags**:
  - `Environment`: dev, staging, production, test
  - `Owner`: (any value)
  - `Application`: (any value)
  - `CostCenter`: engineering, operations, product, finance, marketing

### 4. **EFS File System Tags**
- **Rule Name**: `efs-tagging-enforcement`
- **Resources**: EFS File Systems
- **Required Tags**:
  - `ops:backupschedule1`, `ops:backupschedule2` (same schedule values)
  - `Environment`: dev, staging, production, test
  - `Owner`: (any value)
  - `Application`: (any value)
  - `PerformanceMode`: generalPurpose, maxIO

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Config Rules                         │
├───────────────┬───────────────┬───────────────┬─────────────┤
│   Backup      │     EBS       │     SQS       │     EFS     │
│   Schedule    │   Volume      │    Queue      │  FileSystem │
│   (EC2/RDS)   │               │               │             │
└───────┬───────┴───────┬───────┴───────┬───────┴───────┬─────┘
        │               │               │               │
        ▼               ▼               ▼               ▼
┌───────────────┬───────────────┬───────────────┬─────────────┐
│ backup_tags   │  ebs_tags     │  sqs_tags     │  efs_tags   │
│ Lambda        │  Lambda       │  Lambda       │  Lambda     │
└───────────────┴───────────────┴───────────────┴─────────────┘
        │               │               │               │
        ▼               ▼               ▼               ▼
┌───────────────────────────────────────────────────────────┐
│              AWS Config Compliance Dashboard              │
└───────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
terraform-aft-account-customizations/
├── exceptions/terraform/
│   └── tagging-enforcement.tf          # Main Terraform config
├── modules/
│   ├── lambda/                         # Reusable Lambda module
│   └── scripts/
│       ├── backup-tags/
│       │   ├── backup_tags.py
│       │   └── backup_tags.json
│       ├── ebs-tags/
│       │   ├── ebs_tags.py
│       │   └── ebs_tags.json
│       ├── sqs-tags/
│       │   ├── sqs_tags.py
│       │   └── sqs_tags.json
│       └── efs-tags/
│           ├── efs_tags.py
│           └── efs_tags.json
```

## 🚀 Deployment

### Prerequisites
- AWS Config recorder enabled in target account/region
- Terraform installed (v1.0+)
- AWS credentials configured

### Deploy Steps

1. **Navigate to the exceptions directory**:
```bash
cd terraform-aft-account-customizations/exceptions/terraform
```

2. **Initialize Terraform**:
```bash
terraform init
```

3. **Review the plan**:
```bash
terraform plan
```

4. **Apply the configuration**:
```bash
terraform apply
```

This will create:
- 4 Lambda functions (backup, EBS, SQS, EFS tag validation)
- 4 AWS Config rules
- IAM roles and permissions
- CloudWatch log groups

## ⚙️ Configuration

### Customize Tag Requirements

Edit the JSON files to modify required tags and allowed values:

**EBS Tags** - [ebs_tags.json](modules/scripts/ebs-tags/ebs_tags.json)
```json
{
  "required_tags": {
    "Environment": ["dev", "staging", "production"],
    "Owner": []  // Empty array = any value allowed
  }
}
```

**SQS Tags** - [sqs_tags.json](modules/scripts/sqs-tags/sqs_tags.json)
**EFS Tags** - [efs_tags.json](modules/scripts/efs-tags/efs_tags.json)

### Variable Configuration

Update [variables.tf](exceptions/terraform/variables.tf):

```terraform
variable "config_resource_types" {
  description = "Which resource types to evaluate"
  default = [
    "AWS::EC2::Instance",
    "AWS::EC2::Volume",
    "AWS::RDS::DBInstance"
  ]
}
```

## 📊 Monitoring & Compliance

### View Compliance Status

1. **AWS Console** → Config → Rules
2. Filter by rule name prefix (account-environment)
3. View compliant/non-compliant resources

### CloudWatch Logs

Each Lambda function logs to:
```
/aws/lambda/{account-alias}-{function-name}-function-{environment}
```

### Example Log Output

```
COMPLIANT: All required EBS tags have values matching accepted values.
NON_COMPLIANT: Required SQS tag keys are missing: Owner, Application
NON_COMPLIANT: EFS tag values do not match: Environment=prod
```

## 🔧 Troubleshooting

### Rule Not Triggering

1. Verify AWS Config recorder is enabled:
```bash
aws configservice describe-configuration-recorders
aws configservice describe-configuration-recorder-status
```

2. Check Lambda permissions:
```bash
aws lambda get-policy --function-name {function-name}
```

### False Non-Compliance

1. Check tag format (case-sensitive)
2. Review JSON configuration for typos
3. Examine CloudWatch logs for evaluation details

### Modify Existing Resources

Resources must be updated to trigger re-evaluation:
```bash
# Tag an EBS volume
aws ec2 create-tags --resources vol-xxxxx \
  --tags Key=Environment,Value=production
```

## 🎯 Use Cases

### 1. **Cost Allocation**
Enforce CostCenter tags on SQS queues for chargeback

### 2. **Backup Compliance**
Ensure all EBS volumes and EFS have backup schedules

### 3. **Environment Segmentation**
Validate Environment tags match approved values

### 4. **Operational Ownership**
Require Owner tags for incident response

## 📝 Customization Examples

### Add New Resource Type

1. Create new script directory:
```bash
mkdir modules/scripts/s3-tags
```

2. Create Python validation script (`s3_tags.py`)
3. Create JSON config (`s3_tags.json`)
4. Add Terraform config in [tagging-enforcement.tf](exceptions/terraform/tagging-enforcement.tf)

### Add New Tag Requirement

Edit the appropriate JSON file:
```json
{
  "required_tags": {
    "NewTag": ["value1", "value2", "value3"]
  }
}
```

Then apply Terraform changes:
```bash
terraform apply
```

## 🔒 Security Considerations

- Lambda functions use least-privilege IAM policies
- CloudWatch logs encrypted with KMS (if `kms_key_arn` provided)
- Config rules run in customer account (no data leaves AWS)
- Evaluation results stored in AWS Config

## 📚 Additional Resources

- [AWS Config Custom Rules](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules.html)
- [Lambda Python Runtime](https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html)
- [AWS Control Tower AFT](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)

## 🤝 Contributing

To add new tag enforcement rules:
1. Follow the existing pattern (Python + JSON)
2. Test locally with sample Config events
3. Update this documentation
4. Submit changes via PR

---

**Maintainer**: Cloud Operations Team  
**Last Updated**: January 21, 2026

