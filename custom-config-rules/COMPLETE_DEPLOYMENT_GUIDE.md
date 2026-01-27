# Complete Step-by-Step Guide: EFS TLS Lambda Rule Deployment

## Table of Contents
1. [Understanding the Components](#understanding-the-components)
2. [File Structure Explained](#file-structure-explained)
3. [How It Works](#how-it-works)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Testing and Verification](#testing-and-verification)
6. [Troubleshooting](#troubleshooting)

---

## Understanding the Components

### What Does This Lambda Rule Do?

The Lambda function validates that EFS (Elastic File System) file systems have policies that enforce TLS encryption in transit. Specifically:

- ✅ **COMPLIANT**: EFS has a policy that denies access when `aws:SecureTransport` is `false`
- ❌ **NON_COMPLIANT**: EFS has no policy OR policy doesn't enforce TLS
- ⚠️ **NOT_APPLICABLE**: EFS has been deleted

### Why Use Lambda Instead of Guard Policy?

Guard policies can only check **resource configuration** (like `encrypted: true`), but they **cannot** check the contents of EFS file system **policies** (JSON documents). That's why we need Lambda to:
1. Call `DescribeFileSystemPolicy` API
2. Parse the JSON policy
3. Validate the policy enforces `aws:SecureTransport`

---

## File Structure Explained

### Directory Layout

```
custom-config-rules/
├── scripts/                              # Lambda function code
│   └── efs-tls-enforcement/
│       ├── lambda_function.py           # Main Lambda code
│       ├── test_lambda.py               # Unit tests
│       ├── requirements.txt             # Python dependencies
│       └── example_compliant_policy.json # Sample policy
│
├── iam/                                  # IAM policies
│   └── efs-tls-enforcement.json         # EFS permissions for Lambda
│
├── modules/
│   ├── lambda_rule/                     # Lambda deployment module
│   │   ├── lambda.tf                    # Creates Lambda function
│   │   ├── rule_organization.tf         # Creates org Config rule
│   │   ├── rule_account.tf              # Creates account Config rule
│   │   ├── variables.tf                 # Module inputs
│   │   ├── outputs.tf                   # Module outputs
│   │   └── iam/
│   │       └── lambda_policy.json       # Base Lambda permissions
│   │
│   └── conformance_pack/                # Conformance pack module
│       ├── cpack_organization.tf        # Creates org pack
│       ├── cpack_template.tf            # Generates CloudFormation
│       ├── variables.tf                 # Module inputs
│       └── templates/
│           ├── guard_template.yml       # Guard rule template
│           └── lambda_template.yml     # Lambda rule template
│
└── environments/
    ├── dev/
    │   └── lambda_efs_tls.tf            # Dev: Single account
    └── prd/
        ├── lambda_efs_tls.tf            # Prod: Lambda deployment
        └── cpack_encryption.tf          # Prod: Conformance pack
```

---

## How It Works

### Architecture Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    STEP 1: SETUP PHASE                           │
└─────────────────────────────────────────────────────────────────┘

1. Terraform creates Lambda function from scripts/efs-tls-enforcement/
2. Terraform creates IAM role with permissions:
   - Base: logs, config:PutEvaluations
   - Custom: elasticfilesystem:DescribeFileSystemPolicy
3. Terraform creates Lambda permission (allows Config to invoke)

┌─────────────────────────────────────────────────────────────────┐
│              STEP 2: DEPLOYMENT PHASE                            │
└─────────────────────────────────────────────────────────────────┘

Option A: Dev (Single Account)
   └─> Creates account-level Config rule pointing to Lambda

Option B: Production (Organization)
   ├─> Creates Lambda in management account
   └─> Creates conformance pack with Lambda rule
       └─> Deploys to all member accounts

┌─────────────────────────────────────────────────────────────────┐
│              STEP 3: RUNTIME PHASE                               │
└─────────────────────────────────────────────────────────────────┘

EFS Configuration Changes
    ↓
AWS Config detects change
    ↓
Config invokes Lambda function
    ↓
Lambda calls DescribeFileSystemPolicy API
    ↓
Lambda parses and validates policy
    ↓
Lambda returns compliance to Config
    ↓
Config stores compliance result
```

---

## Step-by-Step Deployment

### Prerequisites

Before starting, ensure you have:

```bash
# 1. AWS CLI configured
aws sts get-caller-identity
# Should show your account ID

# 2. Terraform installed
terraform version
# Should be >= 1.0

# 3. AWS Config enabled
aws configservice describe-configuration-recorders
# Should show active recorder

# 4. S3 bootstrap bucket exists
aws s3 ls | grep bootstrap
# Should show: <account-alias>-bootstrap-use2
```

---

### OPTION A: Dev Environment (Single Account Testing)

**When to use:** Testing the Lambda function in isolation before org-wide rollout

#### Step 1: Review the Lambda Function

```bash
cd /Users/prasanthkorepally/Documents/GitHub/AWS-Terraform-Playground/custom-config-rules

# Read the Lambda code
cat scripts/efs-tls-enforcement/lambda_function.py
```

**Key parts of the Lambda code:**

```python
# Main handler - receives Config events
def lambda_handler(event, context):
    # Parse Config event
    # Extract EFS file system ID
    # Call evaluate_efs_tls_policy()
    # Submit evaluation to Config

# Policy evaluation logic
def evaluate_efs_tls_policy(file_system_id):
    # Call DescribeFileSystemPolicy
    # Parse JSON policy
    # Check for aws:SecureTransport enforcement
    # Return COMPLIANT or NON_COMPLIANT

# Policy checker
def is_secure_transport_enforced(policy):
    # Look for Deny statement with SecureTransport=false
    # This means: Deny access when TLS is NOT used
```

#### Step 2: Test Lambda Locally (Optional)

```bash
cd scripts/efs-tls-enforcement

# Install dependencies
pip3 install boto3

# Run unit tests
python3 test_lambda.py
```

**Expected output:**
```
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

#### Step 3: Review IAM Permissions

```bash
# Base Lambda permissions (logs + Config)
cat modules/lambda_rule/iam/lambda_policy.json

# EFS-specific permissions
cat iam/efs-tls-enforcement.json
```

**What the IAM policies allow:**

```json
// modules/lambda_rule/iam/lambda_policy.json
{
  "logs:CreateLogGroup"        // Create log group
  "logs:CreateLogStream"       // Create log stream
  "logs:PutLogEvents"          // Write logs
  "config:PutEvaluations"      // Submit compliance results
}

// iam/efs-tls-enforcement.json
{
  "elasticfilesystem:DescribeFileSystemPolicy"  // Read EFS policy
  "elasticfilesystem:DescribeFileSystems"       // Read EFS details
}
```

#### Step 4: Review Dev Terraform Configuration

```bash
cat environments/dev/lambda_efs_tls.tf
```

**Key configuration:**

```hcl
module "efs_tls_enforcement_dev" {
  source = "../../modules/lambda_rule"
  
  # IMPORTANT: Single account only
  organization_rule = false
  
  # Lambda configuration
  config_rule_name  = "efs-tls-enforcement-dev"
  lambda_script_dir = "../../scripts/efs-tls-enforcement"
  
  # What resources to check
  resource_types_scope = ["AWS::EFS::FileSystem"]
  
  # When to trigger
  trigger_types = ["ConfigurationItemChangeNotification"]
  
  # Additional permissions
  additional_policies = [
    file("../../iam/efs-tls-enforcement.json")
  ]
}
```

#### Step 5: Deploy to Dev

```bash
cd environments/dev

# Initialize Terraform
terraform init

# Review what will be created
terraform plan
```

**What Terraform will create:**

```
Plan: 5 to add, 0 to change, 0 to destroy

Resources to be created:
1. aws_lambda_function.main
   - Name: efs-tls-enforcement-dev
   - Runtime: python3.12
   - Handler: lambda_function.lambda_handler
   - Code from: S3 (uploaded automatically)

2. aws_iam_role.lambda_role
   - Name: efs-tls-enforcement-dev
   - Trust policy: Lambda service

3. aws_iam_role_policy.base_policy
   - Inline policy: logs + config:PutEvaluations

4. aws_iam_role_policy.efs_policy
   - Inline policy: elasticfilesystem:Describe*

5. aws_config_config_rule.main
   - Name: efs-tls-enforcement-dev
   - Type: Account-level (not organization)
   - Source: Lambda ARN
```

```bash
# Apply the configuration
terraform apply

# Type 'yes' when prompted
```

**Wait 2-3 minutes for deployment to complete.**

#### Step 6: Verify Deployment

```bash
# Check Lambda function
aws lambda get-function \
  --function-name efs-tls-enforcement-dev \
  --region us-east-2

# Check Config rule
aws configservice describe-config-rules \
  --config-rule-names efs-tls-enforcement-dev

# Verify IAM role
aws iam get-role --role-name efs-tls-enforcement-dev

# Check attached policies
aws iam list-role-policies --role-name efs-tls-enforcement-dev
```

#### Step 7: Create Test EFS

```bash
# Create encrypted EFS
EFS_ID=$(aws efs create-file-system \
  --encrypted \
  --tags Key=Name,Value=test-efs-lambda \
  --region us-east-2 \
  --query 'FileSystemId' \
  --output text)

echo "Created EFS: $EFS_ID"

# Wait for EFS to be available
aws efs describe-file-systems \
  --file-system-id $EFS_ID \
  --query 'FileSystems[0].LifeCycleState'
```

#### Step 8: Test Scenario 1 - Compliant Policy

```bash
# Create compliant policy
cat > /tmp/efs-compliant-policy.json << 'EOF'
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
  --policy file:///tmp/efs-compliant-policy.json

echo "Policy applied. Waiting for Config evaluation..."

# Wait 5-10 minutes for Config to evaluate
sleep 600

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID \
  --query 'ComplianceByResources[0].Compliance.ComplianceType' \
  --output text
```

**Expected result:** `COMPLIANT`

#### Step 9: Check Lambda Logs

```bash
# View recent logs
aws logs tail /aws/lambda/efs-tls-enforcement-dev --follow

# Or filter for your EFS
aws logs filter-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement-dev \
  --filter-pattern "$EFS_ID" \
  --query 'events[*].message' \
  --output text
```

**What to look for in logs:**

```
INFO: Received event: {...}
INFO: EFS Policy for fs-12345678: {"Statement": [...]}
INFO: Found Deny statement with aws:SecureTransport=false
INFO: Evaluation submitted: COMPLIANT
```

#### Step 10: Test Scenario 2 - Non-Compliant (No Policy)

```bash
# Remove policy
aws efs delete-file-system-policy --file-system-id $EFS_ID

echo "Policy removed. Waiting for Config evaluation..."

# Wait for evaluation
sleep 600

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID \
  --query 'ComplianceByResources[0].Compliance' \
  --output json
```

**Expected result:**
```json
{
  "ComplianceType": "NON_COMPLIANT",
  "ComplianceContributorCount": {
    "CappedCount": 1,
    "CapExceeded": false
  }
}
```

#### Step 11: Cleanup Dev Testing

```bash
# Delete test EFS
aws efs delete-file-system --file-system-id $EFS_ID

# Optional: Destroy Lambda (if done testing)
cd environments/dev
terraform destroy -target=module.efs_tls_enforcement_dev
```

---

### OPTION B: Production (Organization-Wide with Conformance Pack)

**When to use:** After dev testing succeeds, deploy to all accounts in organization

#### Step 1: Understand Production Architecture

```
Management Account (us-east-2)
├── Lambda: efs-tls-enforcement
├── IAM Role: efs-tls-enforcement
└── Organization Conformance Pack
    ├── Guard Rule: efs-is-encrypted
    ├── Managed Rule: efs-encrypted-check
    └── Lambda Rule: efs-tls-enforcement
        └── References Lambda ARN

Management Account (us-east-1)
├── Lambda: efs-tls-enforcement
├── IAM Role: efs-tls-enforcement
└── Organization Conformance Pack
    ├── Guard Rule: efs-is-encrypted
    ├── Managed Rule: efs-encrypted-check
    └── Lambda Rule: efs-tls-enforcement
        └── References Lambda ARN

Member Accounts (All)
└── Conformance Pack deployed automatically
    └── All 3 rules evaluate resources
```

#### Step 2: Review Production Lambda Deployment

```bash
cd /Users/prasanthkorepally/Documents/GitHub/AWS-Terraform-Playground/custom-config-rules

cat environments/prd/lambda_efs_tls.tf
```

**Key differences from dev:**

```hcl
module "efs_tls_enforcement" {
  source = "../../modules/lambda_rule"
  
  # PRODUCTION: Deploy as organization rule
  organization_rule = true  # <-- This is the key difference!
  
  config_rule_name = "efs-tls-enforcement"
  
  # Exclude accounts where Config is not enabled
  excluded_accounts = [
    "667863416739"  # smrrnd-tst
  ]
}

# Deploy to secondary region
module "efs_tls_enforcement_use1" {
  source = "../../modules/lambda_rule"
  
  providers = {
    aws = aws.use1
  }
  
  organization_rule = true
  config_rule_name = "efs-tls-enforcement"
  excluded_accounts = ["667863416739"]
}
```

#### Step 3: Review Conformance Pack Configuration

```bash
cat environments/prd/cpack_encryption.tf
```

**Understanding the conformance pack:**

```hcl
module "cpack_encryption" {
  source = "../../modules/conformance_pack"
  
  cpack_name = "encryption-validation"
  organization_pack = true  # Deploy to all accounts
  
  # Guard Policy Rules (custom policy as code)
  # Validates EFS encryption at-rest via policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard
  policy_rules_list = [
    {
      config_rule_name     = "efs-is-encrypted"
      config_rule_version  = "2025-10-30"  # References the Guard policy file version
      description          = "Check if EFS is encrypted at-rest"
      resource_types_scope = ["AWS::EFS::FileSystem"]
    }
  ]
  
  # Lambda Custom Rules (our custom Lambda)
  # Validates EFS TLS enforcement for in-transit encryption
  lambda_rules_list = [
    {
      config_rule_name     = "efs-tls-enforcement"
      description          = "Validate EFS policy enforces TLS (in-transit)"
      lambda_function_arn  = module.efs_tls_enforcement.lambda_arn
      resource_types_scope = ["AWS::EFS::FileSystem"]
      message_type         = "ConfigurationItemChangeNotification"
    }
  ]
  
  # This ensures Lambda is created before conformance pack
  depends_on = [module.efs_tls_enforcement]
}
```

#### Step 4: Understand How Conformance Pack Module Works

The conformance pack module generates CloudFormation templates:

```bash
cat modules/conformance_pack/cpack_template.tf
```

**What it does:**

1. **Takes 3 lists of rules:**
   - `policy_rules_list` - Guard policies
   - `managed_rules_list` - AWS managed rules
   - `lambda_rules_list` - Lambda custom rules

2. **Generates CloudFormation YAML:**
   ```yaml
   Resources:
     EfsIsEncrypted:
       Type: AWS::Config::ConfigRule
       Properties:
         ConfigRuleName: account-alias-efs-is-encrypted
         Source:
           Owner: CUSTOM_POLICY
           CustomPolicyDetails:
             PolicyText: |
               rule efsIsEncrypted ...
     
     EfsEncryptedCheck:
       Type: AWS::Config::ConfigRule
       Properties:
         ConfigRuleName: account-alias-efs-encrypted-check
         Source:
           Owner: AWS
           SourceIdentifier: EFS_ENCRYPTED_CHECK
     
     EfsTlsEnforcement:
       Type: AWS::Config::ConfigRule
       Properties:
         ConfigRuleName: account-alias-efs-tls-enforcement
         Source:
           Owner: CUSTOM_LAMBDA
           SourceIdentifier: arn:aws:lambda:...
   ```

3. **Deploys as Organization Conformance Pack:**
   - AWS automatically deploys to all member accounts
   - Each account gets all 3 rules
   - Excluded accounts are skipped

#### Step 5: Deploy Lambda to Production

```bash
cd environments/prd

# Review what will be created
terraform plan -target=module.efs_tls_enforcement \
               -target=module.efs_tls_enforcement_use1
```

**Expected plan:**

```
Plan: 10 to add (5 per region)

us-east-2:
  + aws_lambda_function.efs-tls-enforcement
  + aws_iam_role.efs-tls-enforcement
  + aws_iam_role_policy (2 policies)
  + aws_config_organization_custom_rule.efs-tls-enforcement

us-east-1:
  + aws_lambda_function.efs-tls-enforcement
  + aws_iam_role.efs-tls-enforcement
  + aws_iam_role_policy (2 policies)
  + aws_config_organization_custom_rule.efs-tls-enforcement
```

```bash
# Deploy Lambda functions
terraform apply -target=module.efs_tls_enforcement \
                -target=module.efs_tls_enforcement_use1

# Wait 5 minutes for Lambda deployment
sleep 300
```

#### Step 6: Verify Lambda Deployment

```bash
# Check us-east-2
aws lambda get-function \
  --function-name efs-tls-enforcement \
  --region us-east-2 \
  --query '[FunctionName,Runtime,State]' \
  --output table

# Check us-east-1
aws lambda get-function \
  --function-name efs-tls-enforcement \
  --region us-east-1 \
  --query '[FunctionName,Runtime,State]' \
  --output table

# Check organization rules
aws configservice describe-organization-config-rules \
  --organization-config-rule-names efs-tls-enforcement
```

#### Step 7: Deploy Conformance Pack

```bash
# Review conformance pack plan
terraform plan -target=module.cpack_encryption \
               -target=module.cpack_encryption_use1

# Deploy conformance packs
terraform apply -target=module.cpack_encryption \
                -target=module.cpack_encryption_use1
```

**What happens:**

1. Terraform generates CloudFormation template with all 3 rules
2. Terraform creates Organization Conformance Pack
3. AWS Config deploys pack to all member accounts (except excluded)
4. This takes 15-30 minutes to propagate

#### Step 8: Monitor Conformance Pack Deployment

```bash
# Watch deployment progress
watch -n 30 'aws configservice describe-organization-conformance-pack-statuses \
  --query "OrganizationConformancePackStatuses[?OrganizationConformancePackName==\`$(aws iam list-account-aliases --query AccountAliases[0] --output text)-encryption-validation\`]"'
```

**Status progression:**
- `CREATE_IN_PROGRESS` → Creating
- `CREATE_SUCCESSFUL` → Deployed to all accounts
- `CREATE_FAILED` → Check errors

```bash
# Get detailed status per account
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name $(aws iam list-account-aliases --query AccountAliases[0] --output text)-encryption-validation \
  --query 'OrganizationConformancePackDetailedStatuses[*].[AccountId,Status,ErrorCode]' \
  --output table
```

#### Step 9: Verify Rules in Member Accounts

**Switch to a member account:**

```bash
# Assume role or configure credentials for member account
export AWS_PROFILE=member-account

# List Config rules
aws configservice describe-config-rules \
  --query 'ConfigRules[?contains(ConfigRuleName, `efs`)].ConfigRuleName' \
  --output table
```

**Expected output:**
```
------------------------------------
|      DescribeConfigRules         |
+----------------------------------+
|  account-alias-efs-is-encrypted      |
|  account-alias-efs-encrypted-check   |
|  account-alias-efs-tls-enforcement   |
+----------------------------------+
```

#### Step 10: Test in Member Account

```bash
# Create test EFS in member account
EFS_ID=$(aws efs create-file-system \
  --encrypted \
  --region us-east-2 \
  --query 'FileSystemId' \
  --output text)

# Wait 10 minutes for initial evaluation
sleep 600

# Check compliance (should be NON_COMPLIANT - no policy)
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID \
  --query 'ComplianceByResources[*].[Compliance.ComplianceType]' \
  --output table
```

---

## Testing and Verification

### Test Matrix

| Test Case | EFS Policy | Expected Result | Reason |
|-----------|-----------|-----------------|--------|
| 1 | No policy | NON_COMPLIANT | TLS not enforced |
| 2 | Deny when SecureTransport=false | COMPLIANT | TLS enforced |
| 3 | Allow only when SecureTransport=true | NON_COMPLIANT* | Not best practice |
| 4 | Policy with BoolIfExists | COMPLIANT | TLS enforced |
| 5 | Deleted EFS | NOT_APPLICABLE | Resource gone |

*Note: Lambda logic prioritizes Deny statements as best practice

### Complete Test Script

```bash
#!/bin/bash
# save as: test-efs-lambda-rule.sh

set -e

EFS_ID=$1
if [ -z "$EFS_ID" ]; then
    echo "Usage: $0 <efs-file-system-id>"
    exit 1
fi

echo "Testing EFS: $EFS_ID"

# Test 1: No policy
echo "Test 1: Removing policy..."
aws efs delete-file-system-policy --file-system-id $EFS_ID 2>/dev/null || true
sleep 600
COMPLIANCE=$(aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID \
  --query 'ComplianceByResources[0].Compliance.ComplianceType' \
  --output text)
echo "Result: $COMPLIANCE (Expected: NON_COMPLIANT)"

# Test 2: Compliant policy
echo "Test 2: Applying compliant policy..."
cat > /tmp/policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Principal": "*",
    "Action": "*",
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}
  }]
}
EOF
aws efs put-file-system-policy --file-system-id $EFS_ID --policy file:///tmp/policy.json
sleep 600
COMPLIANCE=$(aws configservice describe-compliance-by-resource \
  --resource-type AWS::EFS::FileSystem \
  --resource-id $EFS_ID \
  --query 'ComplianceByResources[0].Compliance.ComplianceType' \
  --output text)
echo "Result: $COMPLIANCE (Expected: COMPLIANT)"

echo "Tests complete!"
```

---

## Troubleshooting

### Issue 1: Lambda Function Not Creating

**Symptoms:**
```
Error: Error creating Lambda function: InvalidParameterValueException
```

**Solution:**
```bash
# Check S3 bootstrap bucket exists
aws s3 ls | grep bootstrap

# Check bucket region matches
aws s3api get-bucket-location --bucket <account-alias>-bootstrap-use2

# Verify Terraform has permission to upload
aws s3 cp test.txt s3://<account-alias>-bootstrap-use2/test.txt
```

### Issue 2: Lambda Permission Denied

**Symptoms:**
```
AccessDeniedException: User: arn:aws:sts::...assumed-role/efs-tls-enforcement/... 
is not authorized to perform: elasticfilesystem:DescribeFileSystemPolicy
```

**Solution:**
```bash
# Check IAM role exists
aws iam get-role --role-name efs-tls-enforcement

# Check policies attached
aws iam list-role-policies --role-name efs-tls-enforcement

# Verify policy content
aws iam get-role-policy \
  --role-name efs-tls-enforcement \
  --policy-name efs-tls-enforcement-0

# If missing, reapply Terraform
cd environments/prd
terraform apply -target=module.efs_tls_enforcement
```

### Issue 3: Conformance Pack Failed to Deploy

**Symptoms:**
```
Status: CREATE_FAILED
ErrorCode: InsufficientPermissions
```

**Solution:**
```bash
# Check you're in management/delegated admin account
aws organizations describe-organization

# Verify delegated admin
aws organizations list-delegated-administrators \
  --service-principal config.amazonaws.com

# Check Lambda ARN is valid
aws lambda get-function --function-name efs-tls-enforcement

# Verify Lambda in same region as conformance pack
```

### Issue 4: Config Rule Not Evaluating

**Symptoms:**
- No compliance results after 30 minutes

**Solution:**
```bash
# Check Config recorder is running
aws configservice describe-configuration-recorder-status

# Check if EFS resources are being recorded
aws configservice list-discovered-resources \
  --resource-type AWS::EFS::FileSystem

# Manually trigger evaluation
aws configservice start-config-rules-evaluation \
  --config-rule-names efs-tls-enforcement

# Check Lambda logs for errors
aws logs tail /aws/lambda/efs-tls-enforcement --follow
```

### Issue 5: Lambda Timeout

**Symptoms:**
```
Task timed out after 3.00 seconds
```

**Solution:**
```bash
# Check Lambda timeout setting
aws lambda get-function-configuration \
  --function-name efs-tls-enforcement \
  --query Timeout

# Increase timeout in module
# Edit: modules/lambda_rule/lambda.tf
# Add: timeout = 30  (or desired seconds)

# Reapply
terraform apply
```

---

## Summary

You now have:

1. ✅ **Understanding** of how Lambda Config rules work
2. ✅ **Knowledge** of all files and their purposes
3. ✅ **Step-by-step** deployment process for dev and production
4. ✅ **Testing procedures** to verify everything works
5. ✅ **Troubleshooting** guide for common issues

**Next steps:**
- Deploy to dev and test
- After validation, deploy to production
- Monitor compliance across organization
- Adjust excluded accounts as needed

**Questions to ask yourself:**
- Have you tested in dev successfully?
- Do you understand what each file does?
- Are you ready for org-wide deployment?
- Do you know how to troubleshoot issues?

If you answered yes to all, you're ready to deploy! 🚀
