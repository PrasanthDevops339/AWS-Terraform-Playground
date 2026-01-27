# EFS Compliance Rules - Production Deployment Guide

## Quick Start

This guide walks you through deploying EFS encryption and TLS enforcement rules to your AWS Organization.

## Prerequisites Checklist

- [ ] AWS Config enabled in all target accounts
- [ ] AWS Config Recorder running
- [ ] AWS Organizations delegated administrator configured for Config
- [ ] Terraform >= 1.0 installed
- [ ] AWS CLI configured with appropriate credentials
- [ ] S3 bootstrap bucket exists: `<account-alias>-bootstrap-use2`
- [ ] S3 bootstrap bucket exists: `<account-alias>-bootstrap-use1`

## Pre-Deployment Validation

### 1. Verify AWS Config Status

```bash
# Check Config recorder status
aws configservice describe-configuration-recorder-status

# Check Config delivery channel
aws configservice describe-delivery-channel-status
```

### 2. Verify Organization Setup

```bash
# Check delegated administrator
aws organizations list-delegated-administrators \
  --service-principal config.amazonaws.com
```

### 3. Test Lambda Function Locally (Optional)

```bash
cd scripts/efs-tls-enforcement

# Install dependencies
pip install -r requirements.txt boto3

# Run tests
python test_lambda.py
```

Expected output:
```
============================================================
EFS TLS Enforcement Lambda Function - Test Suite
============================================================

Testing: No Policy (Should be NON_COMPLIANT)
Compliance: NON_COMPLIANT
✅ PASSED

Testing: Compliant Policy with Deny + SecureTransport=false
Compliance: COMPLIANT
✅ PASSED

...

🎉 All tests passed!
```

## Deployment Steps

### Phase 1: Deploy to Development (Single Account Testing)

1. **Navigate to dev environment:**
   ```bash
   cd environments/dev
   ```

2. **Review the configuration:**
   ```bash
   cat lambda_efs_tls.tf
   ```
   
   Note: Dev deploys Lambda with **single-account Config rule** (not organization-wide) for testing

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan the deployment:**
   ```bash
   terraform plan -out=tfplan
   ```

   Review the plan carefully. You should see:
   - 1 Lambda function being created (single account)
   - 1 IAM role being created
   - 1 Config rule being created (account-level, NOT organization)
   - No conformance pack changes (testing Lambda only)

5. **Apply to dev:**
   ```bash
   terraform apply tfplan
   ```

6. **Verify dev deployment:**
   ```bash
   # Check Lambda function
   aws lambda get-function --function-name efs-tls-enforcement

   # Check Config rule (account-level)
   aws configservice describe-config-rules \
     --config-rule-names efs-tls-enforcement-dev
   ```

7. **Test in dev:**
   - Create a test EFS file system
   - Apply a compliant policy
   - Wait for Config evaluation
   - Verify compliance status

### Phase 2: Deploy to Production

1. **Navigate to production environment:**
   ```bash
   cd environments/prd
   ```

2. **Review changes since dev:**
   ```bash
   git diff dev/lambda_efs_tls.tf prd/lambda_efs_tls.tf
   git diff dev/cpack_encryption.tf prd/cpack_encryption.tf
   ```

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan the deployment:**
   ```bash
   terraform plan -out=tfplan
   
   # Save plan output for approval
   terraform show -no-color tfplan > tfplan.txt
   ```

5. **Review the plan thoroughly:**
   - Check that excluded accounts are correct
   - Verify Lambda function configurations
   - Confirm conformance pack changes
   - Review IAM permissions

6. **Get approval** (if required by your process)
   - Share `tfplan.txt` with stakeholders
   - Document expected impact
   - Schedule deployment window

7. **Apply to production:**
   ```bash
   terraform apply tfplan
   ```

8. **Monitor the deployment:**
   ```bash
   # Watch conformance pack deployment
   watch -n 10 'aws configservice describe-organization-conformance-pack-statuses \
     --query "OrganizationConformancePackStatuses[?OrganizationConformancePackName==\`<account-alias>-encryption-validation\`]"'
   ```

## Post-Deployment Validation

### 1. Verify Lambda Functions

```bash
# US-EAST-2
aws lambda list-functions \
  --region us-east-2 \
  --query 'Functions[?FunctionName==`efs-tls-enforcement`]'

# US-EAST-1
aws lambda list-functions \
  --region us-east-1 \
  --query 'Functions[?FunctionName==`efs-tls-enforcement`]'
```

### 2. Verify Config Rules

```bash
# Check organization rules
aws configservice describe-organization-config-rules \
  --organization-config-rule-names efs-tls-enforcement

# Check rule status
aws configservice get-organization-config-rule-detailed-status \
  --organization-config-rule-name efs-tls-enforcement
```

### 3. Verify Conformance Packs

```bash
# Check pack status
aws configservice describe-organization-conformance-pack-statuses

# Check pack compliance (after initial evaluation)
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name <account-alias>-encryption-validation
```

### 4. Check Lambda Logs

```bash
# View recent logs
aws logs tail /aws/lambda/efs-tls-enforcement --follow

# Check for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

### 5. Test Compliance Evaluation

Create a test EFS file system in a test account:

```bash
# Create test EFS
aws efs create-file-system \
  --encrypted \
  --tags Key=Name,Value=config-test-efs \
  --region us-east-2

# Get file system ID
EFS_ID=$(aws efs describe-file-systems \
  --query 'FileSystems[?Name==`config-test-efs`].FileSystemId' \
  --output text)

# Apply compliant policy
aws efs put-file-system-policy \
  --file-system-id $EFS_ID \
  --policy file://scripts/efs-tls-enforcement/example_compliant_policy.json

# Wait for Config evaluation (may take up to 10 minutes)
sleep 600

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID
```

## Monitoring

### CloudWatch Alarms

Set up alarms for:

1. **Lambda Errors:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name efs-tls-enforcement-errors \
  --alarm-description "Alert on Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=efs-tls-enforcement
```

2. **Non-Compliant Resources:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name efs-non-compliant-resources \
  --alarm-description "Alert on non-compliant EFS" \
  --metric-name NonCompliantResources \
  --namespace AWS/Config \
  --statistic Maximum \
  --period 3600 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold
```

## Rollback Procedure

If issues occur, follow these steps:

### Option 1: Remove Lambda Rules from Conformance Pack

1. Comment out the `lambda_rules_list` section in `cpack_encryption.tf`
2. Run `terraform plan` and `terraform apply`
3. This keeps the Lambda deployed but removes it from the conformance pack

### Option 2: Full Rollback

1. **Destroy the Lambda functions:**
   ```bash
   terraform destroy -target=module.efs_tls_enforcement
   terraform destroy -target=module.efs_tls_enforcement_use1
   ```

2. **Restore previous conformance pack:**
   ```bash
   git checkout HEAD~1 environments/prd/cpack_encryption.tf
   terraform apply
   ```

3. **Verify rollback:**
   ```bash
   aws configservice describe-organization-conformance-pack-statuses
   ```

## Troubleshooting

### Issue: Lambda Permission Denied

**Symptoms:**
```
Error: AccessDeniedException when calling DescribeFileSystemPolicy
```

**Solution:**
1. Verify IAM policy is attached:
   ```bash
   aws iam list-attached-role-policies \
     --role-name efs-tls-enforcement
   ```

2. Check policy document:
   ```bash
   aws iam get-role-policy \
     --role-name efs-tls-enforcement \
     --policy-name efs-tls-enforcement
   ```

3. If missing, reapply Terraform:
   ```bash
   terraform apply -target=module.efs_tls_enforcement
   ```

### Issue: Conformance Pack CREATE_FAILED

**Symptoms:**
```
Status: CREATE_FAILED
Reason: Lambda function not found
```

**Solution:**
1. Verify Lambda exists:
   ```bash
   aws lambda get-function --function-name efs-tls-enforcement
   ```

2. Check Lambda ARN in conformance pack:
   ```bash
   terraform state show module.cpack_encryption
   ```

3. Ensure depends_on is present in cpack_encryption.tf

### Issue: False Positives (Compliant resources marked NON_COMPLIANT)

**Solution:**
1. Check Lambda logs for specific resource:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/lambda/efs-tls-enforcement \
     --filter-pattern "fs-XXXXXXXX"
   ```

2. Review the EFS file system policy:
   ```bash
   aws efs describe-file-system-policy \
     --file-system-id fs-XXXXXXXX
   ```

3. Validate policy format matches expected pattern

### Issue: Config Rule Not Evaluating

**Solution:**
1. Manually trigger evaluation:
   ```bash
   aws configservice start-config-rules-evaluation \
     --config-rule-names efs-tls-enforcement
   ```

2. Check Config recorder:
   ```bash
   aws configservice describe-configuration-recorder-status
   ```

3. Verify resource is in scope:
   ```bash
   aws configservice list-discovered-resources \
     --resource-type AWS::EFS::FileSystem
   ```

## Maintenance

### Regular Tasks

#### Weekly
- [ ] Review CloudWatch logs for errors
- [ ] Check compliance dashboard
- [ ] Verify no false positives reported

#### Monthly
- [ ] Review excluded accounts list
- [ ] Check for Lambda timeout issues
- [ ] Review and optimize Lambda function if needed
- [ ] Update documentation if processes changed

#### Quarterly
- [ ] Review and update Guard policies
- [ ] Test Lambda function with new scenarios
- [ ] Review AWS Config costs
- [ ] Audit IAM permissions

### Updating Lambda Function

To update the Lambda function code:

1. Modify `scripts/efs-tls-enforcement/lambda_function.py`
2. Test locally: `python test_lambda.py`
3. Apply in dev: `cd environments/dev && terraform apply`
4. Verify in dev environment
5. Apply in prod: `cd environments/prd && terraform apply`

### Updating Guard Policies

To update Guard policies:

1. Create new version: `efs-is-encrypted-YYYY-MM-DD.guard`
2. Update `config_rule_version` in conformance pack
3. Apply changes
4. Old evaluations remain; new evaluations use new policy

## Cost Tracking

Monitor costs using:

```bash
# Get Config costs
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE \
  --filter file://cost-filter.json

# cost-filter.json
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["AWS Config", "AWS Lambda"]
  }
}
```

## Support Contacts

- **AWS Config Issues**: AWS Support
- **Terraform Issues**: DevOps Team
- **Lambda Errors**: Development Team
- **Compliance Questions**: Security Team

## Appendix

### Useful Commands Cheat Sheet

```bash
# List all conformance packs
aws configservice describe-organization-conformance-packs

# Get rule compliance summary
aws configservice describe-conformance-pack-compliance \
  --conformance-pack-name <name> \
  --query 'ConformancePackRuleComplianceSummaries[*].[ConfigRuleName,ConformancePackRuleCompliance]' \
  --output table

# List non-compliant resources
aws configservice describe-compliance-by-config-rule \
  --config-rule-name <rule-name> \
  --compliance-types NON_COMPLIANT

# Force re-evaluation
aws configservice start-config-rules-evaluation \
  --config-rule-names <rule-name>

# Check Lambda last execution
aws lambda get-function --function-name efs-tls-enforcement \
  --query 'Configuration.[LastModified,Runtime,Timeout,MemorySize]' \
  --output table

# View recent Config events
aws configservice describe-configuration-recorder-status
aws configservice describe-delivery-channel-status
```

### File Locations Reference

```
Production Files:
- Lambda Code: scripts/efs-tls-enforcement/lambda_function.py
- Lambda IAM: iam/efs-tls-enforcement.json
- Guard Policy: policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard
- Terraform Config: environments/prd/cpack_encryption.tf
- Lambda Deployment: environments/prd/lambda_efs_tls.tf

Module Files:
- Conformance Pack Module: modules/conformance_pack/
- Lambda Rule Module: modules/lambda_rule/
- Policy Rule Module: modules/policy_rule/

Documentation:
- Main README: README_EFS_COMPLIANCE.md
- This Guide: DEPLOYMENT_GUIDE_EFS.md
```

## Success Criteria

Deployment is successful when:
- ✅ Lambda functions deployed in both regions
- ✅ Config organization rules created
- ✅ Conformance packs updated and in CREATE_SUCCESSFUL status
- ✅ Test EFS with compliant policy shows COMPLIANT
- ✅ Test EFS without policy shows NON_COMPLIANT
- ✅ No errors in Lambda CloudWatch logs
- ✅ All excluded accounts properly excluded
- ✅ Monitoring and alarms configured
