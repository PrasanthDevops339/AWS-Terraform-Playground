# Quick Reference Guide - AWS Config Custom Rules

## Common Commands

### Terraform Operations

```bash
# Initialize
terraform init

# Format code
terraform fmt -recursive

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Destroy specific resource
terraform destroy -target=module.resource_name

# Show state
terraform state list
terraform state show module.resource_name

# Import existing resource
terraform import module.resource_name.aws_resource resource-id
```

### AWS Config Commands

```bash
# List conformance packs
aws configservice describe-organization-conformance-packs

# Get pack status
aws configservice describe-organization-conformance-pack-statuses

# Get pack compliance
aws configservice describe-conformance-pack-compliance \
  --conformance-pack-name <name>

# List config rules
aws configservice describe-organization-config-rules

# Get rule compliance
aws configservice describe-compliance-by-config-rule \
  --config-rule-names <name>

# Force evaluation
aws configservice start-config-rules-evaluation \
  --config-rule-names <name>

# List non-compliant resources
aws configservice describe-compliance-by-config-rule \
  --config-rule-name <name> \
  --compliance-types NON_COMPLIANT

# Get resource compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id fs-12345678

# List discovered resources
aws configservice list-discovered-resources \
  --resource-type AWS::EFS::FileSystem
```

### Lambda Commands

```bash
# List functions
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `efs-tls`)].FunctionName'

# Get function details
aws lambda get-function --function-name efs-tls-enforcement

# Invoke function (test)
aws lambda invoke \
  --function-name efs-tls-enforcement \
  --payload '{"test": "data"}' \
  response.json

# Update function code
aws lambda update-function-code \
  --function-name efs-tls-enforcement \
  --zip-file fileb://function.zip

# Get function configuration
aws lambda get-function-configuration \
  --function-name efs-tls-enforcement
```

### CloudWatch Logs Commands

```bash
# Tail logs
aws logs tail /aws/lambda/efs-tls-enforcement --follow

# Filter errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --filter-pattern "ERROR"

# Get recent logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --start-time $(date -u -d '1 hour ago' +%s)000 \
  --end-time $(date -u +%s)000

# Search specific resource
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --filter-pattern "fs-12345678"
```

### IAM Commands

```bash
# List role policies
aws iam list-attached-role-policies \
  --role-name efs-tls-enforcement

# Get policy document
aws iam get-policy \
  --policy-arn arn:aws:iam::123456789012:policy/policy-name

# Get policy version
aws iam get-policy-version \
  --policy-arn arn:aws:iam::123456789012:policy/policy-name \
  --version-id v1

# Simulate policy
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/role-name \
  --action-names elasticfilesystem:DescribeFileSystemPolicy
```

### EFS Commands

```bash
# List file systems
aws efs describe-file-systems

# Get file system policy
aws efs describe-file-system-policy \
  --file-system-id fs-12345678

# Put file system policy
aws efs put-file-system-policy \
  --file-system-id fs-12345678 \
  --policy file://policy.json

# Delete file system policy
aws efs delete-file-system-policy \
  --file-system-id fs-12345678

# Create file system (for testing)
aws efs create-file-system \
  --encrypted \
  --tags Key=Name,Value=test-efs
```

## File Locations Cheat Sheet

```
Lambda Code:
scripts/efs-tls-enforcement/lambda_function.py

Lambda IAM Policies:
modules/lambda_rule/iam/lambda_policy.json       (base permissions)
iam/efs-tls-enforcement.json                     (EFS permissions)

Guard Policies:
policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard
policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard
policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard

Production Config:
environments/prd/cpack_encryption.tf             (conformance pack)
environments/prd/lambda_efs_tls.tf               (Lambda deployment)
environments/prd/main.tf                         (main config)
environments/prd/versions.tf                     (providers)

Modules:
modules/conformance_pack/                        (conformance pack module)
modules/lambda_rule/                             (Lambda rule module)
modules/policy_rule/                             (policy rule module)

Templates:
modules/conformance_pack/templates/guard_template.yml
modules/conformance_pack/templates/lambda_template.yml
modules/conformance_pack/templates/managed_template.yml
```

## Variable Reference

### Conformance Pack Module Variables

```hcl
cpack_name           = "pack-name"                    # Required
organization_pack    = true                           # Deploy org-wide
excluded_accounts    = ["123456789012"]               # Excluded accounts
random_id            = "xyz123"                       # Optional suffix

policy_rules_list = [
  {
    config_rule_name     = "rule-name"
    config_rule_version  = "2026-01-26"
    description          = "Description"
    policy_runtime       = "guard-2.x.x"              # Optional
    resource_types_scope = ["AWS::Service::Resource"]
  }
]

lambda_rules_list = [
  {
    config_rule_name     = "rule-name"
    description          = "Description"
    lambda_function_arn  = "arn:aws:lambda:..."
    resource_types_scope = ["AWS::Service::Resource"]
    message_type         = "ConfigurationItemChangeNotification"  # Optional
  }
]

managed_rules_list = [
  {
    config_rule_name     = "rule-name"
    description          = "Description"
    source_identifier    = "AWS_MANAGED_RULE_NAME"
    resource_types_scope = ["AWS::Service::Resource"]
    input_parameters     = { key = "value" }          # Optional
  }
]
```

### Lambda Rule Module Variables

```hcl
config_rule_name     = "rule-name"                    # Required
organization_rule    = true                           # Deploy org-wide
description          = "Description"                  # Required
lambda_script_dir    = "../../scripts/dir"            # Required
resource_types_scope = ["AWS::Service::Resource"]    # Required
trigger_types        = ["ConfigurationItemChangeNotification"]  # Optional
additional_policies  = [file("../../iam/policy.json")]  # Optional
excluded_accounts    = ["123456789012"]               # Optional
resource_id_scope    = "resource-id"                  # Optional
```

## Environment Variables for Lambda

```python
# Available in Lambda execution
import os

# AWS SDK automatically configured with:
AWS_REGION                      # Current region
AWS_EXECUTION_ENV               # Lambda execution environment
AWS_LAMBDA_FUNCTION_NAME        # Function name
AWS_LAMBDA_FUNCTION_VERSION     # Function version
AWS_LAMBDA_FUNCTION_MEMORY_SIZE # Memory allocation

# Custom environment variables (if configured)
# Set in modules/lambda_rule/lambda.tf
```

## Config Rule Scopes

```hcl
# Common resource types
resource_types_scope = [
  "AWS::EC2::Instance",
  "AWS::EC2::Volume",
  "AWS::EC2::SecurityGroup",
  "AWS::S3::Bucket",
  "AWS::RDS::DBInstance",
  "AWS::Lambda::Function",
  "AWS::IAM::Role",
  "AWS::IAM::Policy",
  "AWS::EFS::FileSystem",
  "AWS::SQS::Queue",
  "AWS::SNS::Topic",
  "AWS::KMS::Key",
  "AWS::ECS::Cluster",
  "AWS::ECS::Service",
  "AWS::ECS::TaskDefinition",
]
```

## Config Rule Trigger Types

```hcl
trigger_types = [
  "ConfigurationItemChangeNotification",  # Resource change
  "OversizedConfigurationItemChangeNotification",  # Large config change
  "ScheduledNotification",                # Periodic (time-based)
]
```

## Compliance Types

```python
# Use in Lambda evaluations
COMPLIANT               # Resource meets requirements
NON_COMPLIANT          # Resource does not meet requirements
NOT_APPLICABLE         # Rule does not apply (e.g., deleted resource)
INSUFFICIENT_DATA      # Not enough data to evaluate
```

## Testing Checklist

- [ ] Guard policy syntax validated
- [ ] Lambda function tested locally
- [ ] IAM permissions verified
- [ ] Terraform plan reviewed
- [ ] Deployed to dev environment
- [ ] Test resources created and evaluated
- [ ] CloudWatch logs checked for errors
- [ ] Compliance results verified
- [ ] Documentation updated
- [ ] Ready for production deployment

## Deployment Checklist

- [ ] Changes reviewed and approved
- [ ] Terraform plan generated and saved
- [ ] Deployment window scheduled
- [ ] Stakeholders notified
- [ ] Monitoring dashboard ready
- [ ] Rollback plan documented
- [ ] Apply changes
- [ ] Verify deployment
- [ ] Monitor for errors
- [ ] Document any issues

## Rollback Checklist

- [ ] Identify failed component
- [ ] Check error logs
- [ ] Backup current state
- [ ] Revert to previous version
- [ ] Verify rollback
- [ ] Document root cause
- [ ] Plan remediation

## Useful Links

- AWS Config: https://docs.aws.amazon.com/config/
- Guard Language: https://docs.aws.amazon.com/cfn-guard/latest/ug/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/
- Config Rule Examples: https://github.com/awslabs/aws-config-rules
- Lambda Best Practices: https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html

## Support Contacts

| Issue Type | Contact |
|------------|---------|
| AWS Config | AWS Support |
| Terraform | DevOps Team |
| Lambda Errors | Development Team |
| Compliance Questions | Security Team |
| Cost Optimization | FinOps Team |

## Emergency Procedures

### Critical Lambda Failure

```bash
# 1. Disable the Config rule
aws configservice delete-organization-config-rule \
  --organization-config-rule-name <rule-name>

# 2. Check logs
aws logs tail /aws/lambda/function-name --follow

# 3. Fix and redeploy
terraform apply
```

### Conformance Pack Failure

```bash
# 1. Check status
aws configservice describe-organization-conformance-pack-statuses

# 2. Get error details
aws cloudformation describe-stack-events \
  --stack-name <stack-name>

# 3. Delete if needed
aws configservice delete-organization-conformance-pack \
  --organization-conformance-pack-name <name>

# 4. Redeploy
terraform apply
```

### Mass Non-Compliance

```bash
# 1. Check if false positive
# Review Lambda logs and rule logic

# 2. Temporarily exclude accounts
# Edit excluded_accounts in conformance pack

# 3. Fix rule logic
# Update Lambda or Guard policy

# 4. Redeploy and re-evaluate
terraform apply
aws configservice start-config-rules-evaluation \
  --config-rule-names <rule-name>
```

## Tips and Tricks

1. **Use `terraform plan` output for approval**: `terraform show -no-color tfplan > approval.txt`
2. **Test Lambda locally before deploying**: Use `test_lambda.py` script
3. **Check costs regularly**: `aws ce get-cost-and-usage --service CONFIG`
4. **Monitor Lambda cold starts**: Check duration metrics in CloudWatch
5. **Version everything**: Guard policies, Lambda code, Terraform modules
6. **Document exceptions**: Keep track of excluded accounts and why
7. **Use tags**: Tag all resources for easy identification
8. **Set up alerts**: CloudWatch alarms for Lambda errors and non-compliance
9. **Regular reviews**: Monthly review of rules and compliance
10. **Keep it DRY**: Reuse modules, don't duplicate code
