# AWS Config Custom Rules - Organization-wide Deployment

[![Terraform](https://img.shields.io/badge/Terraform-1.0+-purple.svg)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Config-orange.svg)](https://aws.amazon.com/config/)
[![License](https://img.shields.io/badge/License-Internal-blue.svg)]()

Terraform modules for deploying AWS Config rules organization-wide using AWS Config Organization Conformance Packs. Supports Guard policies and custom Lambda rules. (AWS managed rules support available as placeholder for future use.)

## Features

- 🎯 **Organization-wide deployment** via AWS Config Conformance Packs
- 🛡️ **Multiple rule types**:
  - Guard policy rules (custom policy-as-code)
  - Custom Lambda rules (advanced validation logic)
  - AWS managed rules (placeholder - available for future use)
- 🌍 **Multi-region support** (us-east-2, us-east-1)
- 🔐 **Least privilege IAM** permissions
- 📊 **Comprehensive compliance validation**
- 🚀 **Production-ready** with testing and monitoring

## Architecture

```
AWS Organization
│
├── Conformance Packs (Organization-wide)
│   ├── Guard Policy Rules
│   │   └── Custom policy validation (Guard DSL)
│   └── Lambda Custom Rules
│       ├── Lambda Function (Python 3.12)
│       ├── IAM Execution Role
│       └── Config Rule (change-triggered)
│
└── Multi-Region Deployment
    ├── us-east-2 (primary)
    └── us-east-1 (secondary)
```

## Current Rules Deployed

### Encryption Validation Conformance Pack

| Rule Name | Type | Description | Resources |
|-----------|------|-------------|-----------|
| `ebs-is-encrypted` | Guard Policy | Validates EBS volumes are encrypted | EC2::Volume, EC2::Snapshot |
| `sqs-is-encrypted` | Guard Policy | Validates SQS queues are encrypted | SQS::Queue |
| `efs-is-encrypted` | Guard Policy | Validates EFS file systems are encrypted | EFS::FileSystem |
| `efs-encrypted-check` | AWS Managed | AWS native EFS encryption check | EFS::FileSystem |
| `efs-tls-enforcement` | Lambda Custom | Validates EFS policies encrypted at-rest | EFS::FileSystem |
| `efs-tls-enforcement` | Lambda Rule | Validates EFS policies enforce TLS in-transitSecurityGroup |

## Quick Start

### Prerequisites

```bash
# Required
- AWS Config enabled in all accounts
- AWS Organizations configured
- Terraform >= 1.0
- AWS CLI configured

# Optional (for local testing)
- Python 3.12+
- boto3
```

### Basic Deployment

```bash
# Clone repository
git clone <repository-url>
cd custom-config-rules

# Navigate to environment
cd environments/prd

# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Deploy
terraform apply
```

## Repository Structure

```
custom-config-rules/
├── environments/           # Environment-specific configurations
│   ├── dev/               # Development environment
│   │   ├── main.tf
│   │   ├── cpack_encryption.tf
│   │   ├── lambda_efs_tls.tf
│   │   └── variables.tf
│   └── prd/               # Production environment
│       ├── main.tf
│       ├── cpack_encryption.tf
│       ├── lambda_efs_tls.tf
│       └── versions.tf
│
├── modules/               # Reusable Terraform modules
│   ├── conformance_pack/  # Conformance pack module
│   │   ├── cpack_organization.tf
│   │   ├── cpack_template.tf
│   │   ├── variables.tf
│   │   └── templates/
│   │       ├── guard_template.yml
│   │       └── lambda_template.yml
│   ├── lambda_rule/       # Lambda-based custom rules
│   │   ├── lambda.tf
│   │   ├── rule_organization.tf
│   │   ├── outputs.tf
│   │   └── iam/
│   │       └── lambda_policy.json
│   └── policy_rule/       # Policy-based rules (organization)
│       ├── rule_organization.tf
│       └── variables.tf
│
├── scripts/               # Lambda function code
│   └── efs-tls-enforcement/
│       ├── lambda_function.py
│       ├── test_lambda.py
│       ├── requirements.txt
│       └── example_compliant_policy.json
│
├── policies/              # Guard policy definitions
│   ├── ebs-is-encrypted/
│   │   └── ebs-is-encrypted-2026-01-09.guard
│   ├── efs-is-encrypted/
│   │   └── efs-is-encrypted-2025-10-30.guard
│   ├── sqs-is-encrypted/
│   │   └── sqs-is-encrypted-2025-10-30.guard
│   └── port-443-is-open/
│       └── port-443-is-open-2025-06-27.guard
│
├── iam/                   # IAM policies for Lambda functions
│   └── efs-tls-enforcement.json
│
├── README.md              # This file
├── README_EFS_COMPLIANCE.md    # EFS-specific documentation
└── DEPLOYMENT_GUIDE_EFS.md     # Deployment guide
```

## Module Usage

### Conformance Pack Module

Deploy organization-wide conformance packs with mixed rule types:

```hcl
module "cpack_encryption" {
  source            = "../../modules/conformance_pack"
  cpack_name        = "encryption-validation"
  organization_pack = true
  
  excluded_accounts = [
    "123456789012"  # sandbox account
  ]

  # Guard Policy Rules
  policy_rules_list = [
    {
      config_rule_name     = "ebs-is-encrypted"
      config_rule_version  = "2026-01-09"
      description          = "Validates EBS encryption"
      resource_types_scope = ["AWS::EC2::Volume"]
    }
  ]
  
  # AWS Managed Rules
  managed_rules_list = [
    {
      config_rule_name     = "efs-encrypted-check"
      description          = "AWS managed EFS encryption check"
      source_identifier    = "EFS_ENCRYPTED_CHECK"
      resource_types_scope = ["AWS::EFS::FileSystem"]
      input_parameters     = {}
    }
  ]
  
  # Lambda Custom Rules
  lambda_rules_list = [
    {
      config_rule_name     = "efs-tls-enforcement"
      description          = "Custom TLS enforcement validation"
      lambda_function_arn  = module.lambda.lambda_arn
      resource_types_scope = ["AWS::EFS::FileSystem"]
      message_type         = "ConfigurationItemChangeNotification"
    }
  ]
}
```

### Lambda Rule Module

Deploy custom Lambda-based Config rules:

```hcl
module "custom_lambda_rule" {
  source            = "../../modules/lambda_rule"
  organization_rule = true
  config_rule_name  = "custom-validation-rule"
  description       = "Custom validation logic"
  lambda_script_dir = "../../scripts/custom-validation"
  
  resource_types_scope = ["AWS::Service::Resource"]
  trigger_types        = ["ConfigurationItemChangeNotification"]
  
  additional_policies = [
    file("../../iam/custom-permissions.json")
  ]
  
  excluded_accounts = []
}
```

### Policy Rule Module

Deploy organization-wide policy rules:

```hcl
module "policy_rule" {
  source               = "../../modules/policy_rule"
  organization_rule    = true
  config_rule_name     = "custom-policy-rule"
  config_rule_version  = "2026-01-26"
  description          = "Custom policy validation"
  resource_types_scope = ["AWS::Service::Resource"]
  excluded_accounts    = []
}
```

## Detailed Documentation

- **[EFS Compliance README](README_EFS_COMPLIANCE.md)** - Comprehensive guide for EFS encryption and TLS rules
- **[Deployment Guide](DEPLOYMENT_GUIDE_EFS.md)** - Step-by-step deployment instructions
- **[Dev Testing Guide](DEV_TESTING_GUIDE.md)** - Single-account testing in dev environment
- **[Quick Reference](QUICK_REFERENCE.md)** - Commands and shortcuts
- **[Architecture](ARCHITECTURE.md)** - Visual architecture diagrams

## Adding New Rules

### 1. Add a Guard Policy Rule

```bash
# Create policy file
mkdir -p policies/my-new-rule
cat > policies/my-new-rule/my-new-rule-2026-01-26.guard << 'EOF'
rule myNewRule when resourceType == "AWS::Service::Resource" {
    configuration.Property == "Expected Value" <<Resources must meet criteria>>
}
EOF

# Add to conformance pack
# Edit environments/prd/cpack_*.tf
```

### 2. Add an AWS Managed Rule

```hcl
# Edit environments/prd/cpack_*.tf
managed_rules_list = [
  {
    config_rule_name     = "s3-bucket-public-read-prohibited"
    description          = "S3 buckets should not allow public read"
    source_identifier    = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    resource_types_scope = ["AWS::S3::Bucket"]
    input_parameters     = {}
  }
]
```

### 3. Add a Lambda Custom Rule

```bash
# Create Lambda function
mkdir -p scripts/my-lambda-rule
cat > scripts/my-lambda-rule/lambda_function.py << 'EOF'
# Lambda function code
EOF

# Create IAM policy
cat > iam/my-lambda-rule.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [...]
}
EOF

# Deploy Lambda
# Create environments/prd/lambda_my_rule.tf

# Add to conformance pack
# Edit environments/prd/cpack_*.tf
```

## Testing

### Local Lambda Testing

```bash
cd scripts/efs-tls-enforcement

# Install dependencies
pip install -r requirements.txt boto3

# Run tests
python test_lambda.py
```

### Terraform Validation

```bash
# Validate syntax
terraform validate

# Check formatting
terraform fmt -check -recursive

# Plan without applying
terraform plan
```

### Integration Testing

```bash
# Create test resource in dev account
aws efs create-file-system --encrypted --region us-east-2

# Wait for Config evaluation
sleep 300

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem
```

## Monitoring

### CloudWatch Dashboard

```bash
# Create monitoring dashboard
aws cloudwatch put-dashboard \
  --dashboard-name Config-Rules-Monitoring \
  --dashboard-body file://cloudwatch-dashboard.json
```

### CloudWatch Alarms

```bash
# Lambda errors alarm
aws cloudwatch put-metric-alarm \
  --alarm-name config-lambda-errors \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold
```

### Compliance Reporting

```bash
# Get conformance pack compliance
aws configservice describe-conformance-pack-compliance \
  --conformance-pack-name <pack-name>

# Export compliance report
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name <rule-name> \
  --compliance-types NON_COMPLIANT > compliance-report.json
```

## Cost Estimation

| Component | Quantity | Unit Cost | Monthly Cost |
|-----------|----------|-----------|--------------|
| Config Rules | 6 rules × 2 regions × 100 accounts | $2/rule | ~$2,400 |
| Lambda Invocations | ~10,000/month | Free tier | $0 |
| Lambda Duration | ~500ms avg | Free tier | $0 |
| S3 Storage | ~50MB | $0.023/GB | $0.01 |
| CloudWatch Logs | ~1GB/month | $0.50/GB | $0.50 |
| **Total** | | | **~$2,400/month** |

*Note: Costs scale with number of accounts and resources*

## Troubleshooting

### Common Issues

**Issue: Conformance pack deployment failed**
```bash
# Check pack status
aws configservice describe-organization-conformance-pack-statuses

# View detailed errors
aws cloudformation describe-stack-events \
  --stack-name <pack-stack-name>
```

**Issue: Lambda function errors**
```bash
# View logs
aws logs tail /aws/lambda/efs-tls-enforcement --follow

# Check permissions
aws iam simulate-principal-policy \
  --policy-source-arn <role-arn> \
  --action-names elasticfilesystem:DescribeFileSystemPolicy
```

**Issue: Resources not being evaluated**
```bash
# Check Config recorder
aws configservice describe-configuration-recorder-status

# Manually trigger evaluation
aws configservice start-config-rules-evaluation \
  --config-rule-names <rule-name>
```

## Best Practices

1. **Version Control**: Always version Guard policies (YYYY-MM-DD format)
2. **Testing**: Test in dev before deploying to production
3. **Least Privilege**: Grant only necessary IAM permissions
4. **Multi-Region**: Deploy critical rules to multiple regions
5. **Monitoring**: Set up CloudWatch alarms for Lambda errors
6. **Documentation**: Document custom rules and their purpose
7. **Excluded Accounts**: Document why accounts are excluded
8. **Incremental Rollout**: Deploy to small account sets first

## Security

- All Lambda functions use least privilege IAM roles
- Config service roles follow AWS best practices
- S3 buckets for Lambda code are encrypted
- No hardcoded credentials in any code
- Secrets managed via AWS Secrets Manager (if needed)

## Contributing

1. Create feature branch from `main`
2. Make changes following existing patterns
3. Test in dev environment
4. Update documentation
5. Submit pull request with detailed description
6. Ensure CI/CD checks pass

## Support

For issues or questions:
- Check [Troubleshooting](#troubleshooting) section
- Review CloudWatch logs
- Contact DevOps team
- Open GitHub issue (if applicable)

## License

Internal use only. All rights reserved.

## Changelog

### 2026-01-26
- Added Lambda custom rule support to conformance packs
- Added EFS TLS enforcement Lambda rule
- Removed AWS Managed rule dependency (using Guard policy for at-rest validation)
- Enhanced conformance pack module with Guard and Lambda rule support
- Added comprehensive EFS compliance matrix documentation

### 2026-01-09
- Updated EBS encryption policy to version 2026-01-09

### 2025-10-30
- Initial Guard policies for EBS, SQS, and EFS encryption

### 2025-06-27
- Added port-443-is-open policy rule

## Authors

Platform Core Services Team
Technology Delivery - DTD04

## Acknowledgments

- AWS Config documentation
- AWS Guard documentation
- Terraform AWS Provider documentation

