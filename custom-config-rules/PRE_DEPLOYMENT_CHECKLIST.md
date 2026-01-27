# Pre-Deployment Checklist - EFS Compliance Rules

## Phase 1: Local Validation ✓

### Code Review
- [ ] Review Lambda function code: [lambda_function.py](scripts/efs-tls-enforcement/lambda_function.py)
- [ ] Review IAM policies: [efs-tls-enforcement.json](iam/efs-tls-enforcement.json)
- [ ] Review Terraform configurations: [lambda_efs_tls.tf](environments/prd/lambda_efs_tls.tf)
- [ ] Review conformance pack config: [cpack_encryption.tf](environments/prd/cpack_encryption.tf)

### Local Testing
```bash
# Test Lambda function locally
cd scripts/efs-tls-enforcement
pip install -r requirements.txt boto3
python test_lambda.py
# Expected: ✅ All tests passed!
```
- [ ] Lambda tests pass locally
- [ ] No syntax errors
- [ ] All test scenarios pass

### Terraform Validation
```bash
cd environments/prd
terraform fmt -recursive -check
terraform validate
```
- [ ] Terraform formatting correct
- [ ] Terraform validation passes
- [ ] No deprecated syntax

## Phase 2: Prerequisites ✓

### AWS Account Setup
- [ ] AWS Config enabled in all target accounts
- [ ] Config Recorder running in all accounts
- [ ] AWS Organizations configured
- [ ] Delegated administrator for Config set up

**Verify:**
```bash
aws configservice describe-configuration-recorder-status
aws organizations list-delegated-administrators --service-principal config.amazonaws.com
```

### S3 Bootstrap Buckets
- [ ] S3 bucket exists: `<account-alias>-bootstrap-use2`
- [ ] S3 bucket exists: `<account-alias>-bootstrap-use1`
- [ ] Buckets have encryption enabled
- [ ] Buckets have versioning enabled

**Verify:**
```bash
aws s3 ls | grep bootstrap
aws s3api get-bucket-encryption --bucket <account-alias>-bootstrap-use2
aws s3api get-bucket-versioning --bucket <account-alias>-bootstrap-use2
```

### Terraform Backend
- [ ] Terraform backend configured
- [ ] State file location confirmed
- [ ] State locking enabled
- [ ] Backend credentials valid

**Verify:**
```bash
cd environments/prd
terraform init
# Should initialize successfully
```

### IAM Permissions
- [ ] Terraform execution role has required permissions:
  - `lambda:*` (Create functions, roles, permissions)
  - `config:*` (Create rules, conformance packs)
  - `iam:*` (Create roles, policies)
  - `s3:*` (Upload Lambda code)
  - `organizations:*` (Create org resources)

**Verify:**
```bash
aws sts get-caller-identity
aws iam list-attached-user-policies --user-name <your-user>
```

## Phase 3: Dev Environment Testing ✓

### Deploy to Dev
```bash
cd environments/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
- [ ] Terraform plan reviewed
- [ ] No unexpected changes
- [ ] Apply completed successfully
- [ ] No errors in output

**Note:** Dev deploys Lambda with single-account Config rule (NOT organization-wide)

### Verify Dev Deployment
```bash
# Check Lambda function
aws lambda get-function --function-name efs-tls-enforcement-dev --region us-east-2

# Check Config rule (account-level, NOT organization)
aws configservice describe-config-rules --config-rule-names efs-tls-enforcement-dev
```
- [ ] Lambda function created
- [ ] Config rule created (account-level)
- [ ] No errors

### Create Test EFS in Dev
```bash
# Create test EFS
aws efs create-file-system \
  --encrypted \
  --tags Key=Name,Value=config-test-efs \
  --region us-east-2

# Get file system ID
EFS_ID=$(aws efs describe-file-systems \
  --query 'FileSystems[?Tags[?Key==`Name` && Value==`config-test-efs`]].FileSystemId' \
  --output text)

echo "Test EFS ID: $EFS_ID"
```
- [ ] Test EFS created successfully
- [ ] EFS ID captured

### Test Scenario 1: Compliant Policy
```bash
# Apply compliant policy
aws efs put-file-system-policy \
  --file-system-id $EFS_ID \
  --policy file://scripts/efs-tls-enforcement/example_compliant_policy.json

# Wait for evaluation (5-10 minutes)
sleep 600

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID
```
- [ ] Policy applied successfully
- [ ] Config evaluation triggered
- [ ] Resource shows COMPLIANT
- [ ] All three EFS rules show COMPLIANT

### Test Scenario 2: Non-Compliant (No Policy)
```bash
# Remove policy
aws efs delete-file-system-policy --file-system-id $EFS_ID

# Wait for evaluation
sleep 600

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID
```
- [ ] Policy removed successfully
- [ ] Config evaluation triggered
- [ ] Resource shows NON_COMPLIANT for TLS rule
- [ ] Annotation explains missing policy

### Check Lambda Logs in Dev
```bash
aws logs tail /aws/lambda/efs-tls-enforcement-dev --follow --region us-east-2
```
- [ ] Lambda executions logged
- [ ] No ERROR messages
- [ ] Compliance evaluations visible
- [ ] Annotations are clear

### Clean Up Dev Test Resources
```bash
# Delete test EFS
aws efs delete-file-system --file-system-id $EFS_ID
```
- [ ] Test resources cleaned up

## Phase 4: Production Preparation ✓

### Documentation Review
- [ ] [README.md](README.md) reviewed
- [ ] [README_EFS_COMPLIANCE.md](README_EFS_COMPLIANCE.md) reviewed
- [ ] [DEPLOYMENT_GUIDE_EFS.md](DEPLOYMENT_GUIDE_EFS.md) reviewed
- [ ] [ARCHITECTURE.md](ARCHITECTURE.md) reviewed
- [ ] All documentation accurate

### Stakeholder Communication
- [ ] Security team notified
- [ ] FinOps team notified (costs)
- [ ] Account owners notified
- [ ] Deployment window scheduled
- [ ] Rollback plan communicated

### Excluded Accounts Review
```hcl
# Review excluded accounts in:
# environments/prd/cpack_encryption.tf
# environments/prd/lambda_efs_tls.tf

excluded_accounts = [
  "123456789012",  # Reason: Config not enabled
  "234567890123",  # Reason: Test account
]
```
- [ ] Excluded accounts list reviewed
- [ ] Each exclusion documented with reason
- [ ] Security team approved exclusions

### Cost Approval
**Estimated Monthly Cost:**
- Config Rules: ~$2,400/month (6 rules × 2 regions × 100 accounts)
- Lambda: ~$0/month (within free tier)
- Total: ~$2,400.51/month

- [ ] Cost estimate reviewed
- [ ] FinOps team approved
- [ ] Budget allocated

### Change Management
- [ ] Change ticket created
- [ ] Approval obtained
- [ ] Deployment window confirmed
- [ ] On-call support notified

## Phase 5: Production Deployment ✓

### Pre-Deployment Backup
```bash
cd environments/prd

# Backup current state
terraform state pull > state-backup-$(date +%Y%m%d-%H%M%S).json

# Save current conformance pack config
aws configservice describe-organization-conformance-packs \
  > conformance-packs-backup-$(date +%Y%m%d-%H%M%S).json
```
- [ ] State file backed up
- [ ] Current config backed up
- [ ] Backups stored securely

### Terraform Plan Review
```bash
cd environments/prd
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan-approval.txt
```
- [ ] Plan generated
- [ ] Plan output saved
- [ ] Plan reviewed by team
- [ ] No unexpected changes
- [ ] Approvals obtained

### Production Deployment
```bash
# Deploy
terraform apply tfplan

# Monitor
watch -n 10 'aws configservice describe-organization-conformance-pack-statuses'
```
- [ ] Apply started
- [ ] Monitoring in place
- [ ] No immediate errors

### Deployment Progress Checks

**After 5 minutes:**
```bash
# Check Lambda functions
aws lambda list-functions --region us-east-2 | grep efs-tls
aws lambda list-functions --region us-east-1 | grep efs-tls
```
- [ ] Lambda functions created in us-east-2
- [ ] Lambda functions created in us-east-1

**After 10 minutes:**
```bash
# Check Config rules
aws configservice describe-organization-config-rules \
  --organization-config-rule-names efs-tls-enforcement
```
- [ ] Organization config rules created

**After 15 minutes:**
```bash
# Check conformance pack status
aws configservice describe-organization-conformance-pack-statuses \
  --query 'OrganizationConformancePackStatuses[?OrganizationConformancePackName==`<account-alias>-encryption-validation`]'
```
- [ ] Conformance packs deploying
- [ ] Status is CREATE_IN_PROGRESS or CREATE_SUCCESSFUL

**After 30 minutes:**
```bash
# Get detailed status
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name <account-alias>-encryption-validation
```
- [ ] All accounts show successful deployment (or properly excluded)
- [ ] No unexpected failures

## Phase 6: Post-Deployment Validation ✓

### Lambda Function Validation
```bash
# Check Lambda in us-east-2
aws lambda get-function-configuration \
  --function-name efs-tls-enforcement \
  --region us-east-2

# Check Lambda in us-east-1
aws lambda get-function-configuration \
  --function-name efs-tls-enforcement \
  --region us-east-1
```
- [ ] Functions exist
- [ ] Runtime is Python 3.12
- [ ] Memory is 128 MB
- [ ] Timeout is appropriate
- [ ] IAM role attached

### IAM Permissions Validation
```bash
# Check Lambda role
aws iam get-role --role-name efs-tls-enforcement

# Check attached policies
aws iam list-attached-role-policies --role-name efs-tls-enforcement
```
- [ ] Role exists
- [ ] Base policy attached (logs, config)
- [ ] EFS policy attached
- [ ] Trust relationship correct

### Config Rule Validation
```bash
# Get rule details
aws configservice describe-organization-config-rules \
  --organization-config-rule-names efs-tls-enforcement

# Check rule status across accounts
aws configservice get-organization-config-rule-detailed-status \
  --organization-config-rule-name efs-tls-enforcement
```
- [ ] Rule deployed to all accounts (except excluded)
- [ ] No deployment failures
- [ ] Scope is correct (AWS::EFS::FileSystem)

### Conformance Pack Validation
```bash
# Get pack compliance
aws configservice describe-conformance-pack-compliance \
  --conformance-pack-name <account-alias>-encryption-validation
```
- [ ] Pack deployed successfully
- [ ] All rules active
- [ ] Guard rules working
- [ ] Managed rules working
- [ ] Lambda rules working

### Lambda Logs Check
```bash
# Check for errors in us-east-2
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --filter-pattern "ERROR" \
  --region us-east-2

# Check for errors in us-east-1
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --filter-pattern "ERROR" \
  --region us-east-1
```
- [ ] No ERROR messages
- [ ] Successful evaluations logged
- [ ] Log format correct

### Sample Evaluation Check
```bash
# Pick a random EFS in an account
aws efs describe-file-systems --region us-east-2 | head -n 1

# Check its compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id <fs-id>
```
- [ ] Sample EFS evaluated
- [ ] Compliance status appropriate
- [ ] All three EFS rules evaluated
- [ ] Annotations clear

## Phase 7: Monitoring Setup ✓

### CloudWatch Alarms
```bash
# Lambda errors alarm
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
  --dimensions Name=FunctionName,Value=efs-tls-enforcement \
  --region us-east-2
```
- [ ] Lambda error alarm created
- [ ] Non-compliance alarm created (optional)
- [ ] SNS topics configured
- [ ] Team members subscribed

### Log Retention
```bash
# Set retention for Lambda logs
aws logs put-retention-policy \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --retention-in-days 30 \
  --region us-east-2

aws logs put-retention-policy \
  --log-group-name /aws/lambda/efs-tls-enforcement \
  --retention-in-days 30 \
  --region us-east-1
```
- [ ] Log retention set (30 days recommended)
- [ ] Cost impact understood

## Phase 8: Documentation and Handoff ✓

### Update Documentation
- [ ] Deployment date added to changelog
- [ ] Any deployment issues documented
- [ ] Known issues documented
- [ ] Contact information current

### Team Handoff
- [ ] Operations team briefed
- [ ] Runbook reviewed
- [ ] Escalation path confirmed
- [ ] Knowledge transfer complete

### Post-Deployment Meeting
- [ ] Deployment summary presented
- [ ] Metrics reviewed
- [ ] Feedback collected
- [ ] Next steps identified

## Phase 9: Monitoring Period ✓

### Day 1 Checks
```bash
# Check for errors
aws logs tail /aws/lambda/efs-tls-enforcement --follow

# Check compliance trends
aws configservice describe-conformance-pack-compliance \
  --conformance-pack-name <account-alias>-encryption-validation
```
- [ ] No critical errors
- [ ] Compliance evaluations running
- [ ] No false positives reported

### Week 1 Review
- [ ] No major issues reported
- [ ] Lambda performance acceptable
- [ ] Compliance results accurate
- [ ] Cost tracking enabled
- [ ] Team comfortable with operations

### Month 1 Review
- [ ] Cost estimate validated
- [ ] Compliance trends analyzed
- [ ] False positives addressed
- [ ] Documentation updated
- [ ] Lessons learned documented

## Rollback Plan (If Needed) 🔄

### Quick Rollback: Remove Lambda Rules from Pack
```bash
# Edit cpack_encryption.tf
# Comment out lambda_rules_list section
# Apply changes
cd environments/prd
terraform apply
```
- [ ] Lambda rules removed from pack
- [ ] Guard and managed rules remain
- [ ] Lambdas still deployed but not evaluated

### Full Rollback: Restore Previous State
```bash
# Restore state backup
cd environments/prd
terraform state push state-backup-<timestamp>.json

# Or: Destroy new resources
terraform destroy -target=module.efs_tls_enforcement
terraform destroy -target=module.efs_tls_enforcement_use1

# Restore previous conformance pack
git checkout HEAD~1 environments/prd/cpack_encryption.tf
terraform apply
```
- [ ] Previous state restored
- [ ] Resources destroyed
- [ ] Conformance pack reverted

### Post-Rollback Actions
- [ ] Root cause analysis completed
- [ ] Issue documented
- [ ] Fix identified
- [ ] Re-deployment plan created

---

## Sign-Off ✍️

### Dev Environment Testing
- [ ] **Tested By:** _________________ **Date:** _________
- [ ] **Approved By:** _________________ **Date:** _________

### Production Deployment Approval
- [ ] **Security Team:** _________________ **Date:** _________
- [ ] **FinOps Team:** _________________ **Date:** _________
- [ ] **Platform Team:** _________________ **Date:** _________

### Post-Deployment Validation
- [ ] **Validated By:** _________________ **Date:** _________
- [ ] **Sign-off By:** _________________ **Date:** _________

---

## Success Criteria Summary

### Deployment Successful If:
- ✅ All Terraform applies completed without errors
- ✅ Lambda functions deployed to both regions
- ✅ Conformance packs in CREATE_SUCCESSFUL status
- ✅ Sample EFS evaluations show correct compliance
- ✅ No Lambda errors in CloudWatch logs
- ✅ Monitoring dashboard operational
- ✅ Team trained and comfortable

### Ready for Production Sign-off If:
- ✅ All checklist items completed
- ✅ Week 1 monitoring shows stability
- ✅ No false positives reported
- ✅ Documentation complete
- ✅ Team handoff complete

---

**Checklist Version:** 1.0  
**Last Updated:** 2026-01-26  
**Maintained By:** Platform Core Services Team
