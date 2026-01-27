# Dev Environment Testing Guide - EFS TLS Lambda Rule

## Overview

The dev environment deploys the EFS TLS enforcement Lambda rule to a **single account** (not organization-wide) for testing purposes.

## Key Differences: Dev vs Production

| Aspect | Dev | Production |
|--------|-----|------------|
| Deployment Scope | Single account | Organization-wide |
| Config Rule Type | Account-level | Organization |
| Conformance Pack | No | Yes |
| Multi-region | Single region | us-east-2 + us-east-1 |
| Lambda Function Name | `efs-tls-enforcement-dev` | `efs-tls-enforcement` |
| Config Rule Name | `efs-tls-enforcement-dev` | `efs-tls-enforcement` |

## Quick Start

### 1. Deploy Lambda Rule to Dev Account

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

**What gets created:**
- Lambda function: `efs-tls-enforcement-dev`
- IAM execution role with EFS permissions
- Account-level Config rule (NOT organization-wide)

### 2. Create Test EFS File System

```bash
# Create encrypted EFS
aws efs create-file-system \
  --encrypted \
  --tags Key=Name,Value=test-efs-dev \
  --region us-east-2

# Get file system ID
EFS_ID=$(aws efs describe-file-systems \
  --query 'FileSystems[?Tags[?Key==`Name` && Value==`test-efs-dev`]].FileSystemId' \
  --output text)

echo "Test EFS ID: $EFS_ID"
```

### 3. Test Scenario: Compliant Policy

```bash
# Create compliant policy
cat > /tmp/efs-policy.json << 'EOF'
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
EOF

# Apply policy to EFS
aws efs put-file-system-policy \
  --file-system-id $EFS_ID \
  --policy file:///tmp/efs-policy.json

# Wait 5-10 minutes for Config evaluation
sleep 600

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID \
  --query 'ComplianceByResources[*].[ResourceType,ResourceId,Compliance.ComplianceType]' \
  --output table
```

**Expected Result:** `COMPLIANT`

### 4. Test Scenario: Non-Compliant (No Policy)

```bash
# Remove policy
aws efs delete-file-system-policy --file-system-id $EFS_ID

# Wait for evaluation
sleep 600

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID \
  --query 'ComplianceByResources[*].[ResourceType,ResourceId,Compliance.ComplianceType]' \
  --output table
```

**Expected Result:** `NON_COMPLIANT`

### 5. Check Lambda Logs

```bash
# View recent logs
aws logs tail /aws/lambda/efs-tls-enforcement-dev --follow

# Check for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement-dev \
  --filter-pattern "ERROR"

# Search for specific EFS
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement-dev \
  --filter-pattern "$EFS_ID"
```

### 6. Manual Trigger Evaluation

```bash
# Force Config to re-evaluate
aws configservice start-config-rules-evaluation \
  --config-rule-names efs-tls-enforcement-dev
```

### 7. Cleanup

```bash
# Delete test EFS
aws efs delete-file-system --file-system-id $EFS_ID

# Optionally destroy Lambda (keep for more testing)
# cd environments/dev
# terraform destroy -target=module.efs_tls_enforcement_dev
```

## Verification Checklist

After deployment, verify:

- [ ] Lambda function exists: `efs-tls-enforcement-dev`
- [ ] Lambda execution role has EFS permissions
- [ ] Config rule exists (account-level, not org)
- [ ] Test EFS with policy shows COMPLIANT
- [ ] Test EFS without policy shows NON_COMPLIANT
- [ ] Lambda logs show successful evaluations
- [ ] No ERROR messages in logs
- [ ] Policy parsing works correctly

## Troubleshooting

### Lambda Not Triggering

```bash
# Check if Config is recording EFS resources
aws configservice describe-configuration-recorders

# Check recorder status
aws configservice describe-configuration-recorder-status

# Manually trigger
aws configservice start-config-rules-evaluation \
  --config-rule-names efs-tls-enforcement-dev
```

### Permission Errors

```bash
# Check Lambda role
aws iam get-role --role-name efs-tls-enforcement-dev

# Check attached policies
aws iam list-attached-role-policies \
  --role-name efs-tls-enforcement-dev

# Check inline policies
aws iam list-role-policies \
  --role-name efs-tls-enforcement-dev
```

### Lambda Timeout

```bash
# Check Lambda configuration
aws lambda get-function-configuration \
  --function-name efs-tls-enforcement-dev \
  --query '[Timeout,MemorySize,Runtime]' \
  --output table

# Increase timeout if needed (via Terraform)
# Edit environments/dev/lambda_efs_tls.tf
```

### False Positives/Negatives

```bash
# Get detailed evaluation
aws configservice describe-compliance-by-config-rule \
  --config-rule-name efs-tls-enforcement-dev \
  --query 'ComplianceByConfigRules[0]'

# Check Lambda logs for policy content
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement-dev \
  --filter-pattern "EFS Policy"
```

## Testing Checklist

### Basic Functionality
- [ ] Lambda deploys successfully
- [ ] Lambda can be invoked manually
- [ ] Lambda has correct IAM permissions
- [ ] Config rule is active

### Compliance Scenarios
- [ ] EFS with compliant policy → COMPLIANT
- [ ] EFS without policy → NON_COMPLIANT
- [ ] EFS with non-compliant policy → NON_COMPLIANT
- [ ] Deleted EFS → NOT_APPLICABLE

### Edge Cases
- [ ] Very long policy (close to EFS limit)
- [ ] Policy with multiple statements
- [ ] Policy with BoolIfExists condition
- [ ] Policy with complex conditions

### Performance
- [ ] Lambda executes in < 5 seconds
- [ ] No Lambda timeouts
- [ ] Concurrent executions handled
- [ ] Cold start time acceptable

## Moving to Production

Once dev testing is complete:

1. **Verify all test scenarios pass**
2. **Review Lambda logs for any issues**
3. **Update production configuration:**
   - Set `organization_rule = true`
   - Remove `-dev` suffix from names
   - Add to conformance pack
4. **Deploy to production**
5. **Monitor rollout across organization**

## Commands Reference

```bash
# Deploy
cd environments/dev && terraform apply

# Check Lambda
aws lambda get-function --function-name efs-tls-enforcement-dev

# Check Config rule
aws configservice describe-config-rules \
  --config-rule-names efs-tls-enforcement-dev

# View logs
aws logs tail /aws/lambda/efs-tls-enforcement-dev --follow

# Check compliance
aws configservice describe-compliance-by-config-rule \
  --config-rule-name efs-tls-enforcement-dev

# Cleanup
aws efs delete-file-system --file-system-id <fs-id>
terraform destroy -target=module.efs_tls_enforcement_dev
```

## Next Steps

After successful dev testing:
1. Document any findings
2. Update Lambda code if needed
3. Proceed to production deployment
4. See: [DEPLOYMENT_GUIDE_EFS.md](DEPLOYMENT_GUIDE_EFS.md)
