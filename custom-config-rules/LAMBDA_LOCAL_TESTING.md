# Lambda Rule Local Testing Guide

## Overview
This guide provides step-by-step instructions for testing the EFS TLS Enforcement Lambda function locally before deployment to AWS.

## Prerequisites

### 1. Python Environment
```bash
# Verify Python 3.8+ is installed
python3 --version

# Should output: Python 3.8.x or higher
```

### 2. Required Tools
- Python 3.8 or higher
- pip (Python package manager)
- Git (for cloning/accessing repository)

## Setup Instructions

### Step 1: Navigate to Lambda Script Directory
```bash
cd /Users/prasanthkorepally/Documents/GitHub/AWS-Terraform-Playground/custom-config-rules/scripts/efs-tls-enforcement
```

### Step 2: Create Python Virtual Environment (Recommended)
```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # macOS/Linux
# OR
venv\Scripts\activate     # Windows
```

### Step 3: Install Dependencies (Optional for Local Testing)
```bash
# Install required Python packages
pip install -r requirements.txt

# Verify installation
pip list | grep boto3
# Should show: boto3 1.26.0 or higher

# NOTE: The test suite mocks boto3, so tests can run even without boto3 installed
# boto3 is only required when deploying to AWS Lambda
```

## Running the Tests

### Step 4: Execute Test Suite
```bash
# Run all test scenarios
python3 test_lambda.py
```

### Expected Output
```
============================================================
EFS TLS Enforcement Lambda Function - Test Suite
============================================================

============================================================
Testing: No Policy (Should be NON_COMPLIANT)
============================================================
No policy found for EFS file system: fs-12345678
Compliance: NON_COMPLIANT
Annotation: EFS file system has no policy - TLS enforcement not configured
✅ PASSED - Expected NON_COMPLIANT, got NON_COMPLIANT

============================================================
Testing: Compliant Policy with Deny + Action=* + SecureTransport=false
============================================================
Compliance: COMPLIANT
Annotation: EFS file system policy enforces TLS (aws:SecureTransport) for client actions
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Testing: Compliant Policy with specific EFS client actions
============================================================
Compliance: COMPLIANT
Annotation: EFS file system policy enforces TLS (aws:SecureTransport) for client actions
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Testing: Compliant Policy with elasticfilesystem:* action
============================================================
Compliance: COMPLIANT
Annotation: EFS file system policy enforces TLS (aws:SecureTransport) for client actions
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Testing: Compliant Policy with elasticfilesystem:Client* pattern
============================================================
Compliance: COMPLIANT
Annotation: EFS file system policy enforces TLS (aws:SecureTransport) for client actions
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Testing: Compliant Policy with BoolIfExists condition
============================================================
Compliance: COMPLIANT
Annotation: EFS file system policy enforces TLS (aws:SecureTransport) for client actions
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Testing: Non-Compliant Policy (No SecureTransport enforcement)
============================================================
No valid SecureTransport enforcement found for EFS client actions
Compliance: NON_COMPLIANT
Annotation: EFS file system policy does not enforce TLS (aws:SecureTransport) for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)
✅ PASSED - Expected NON_COMPLIANT, got NON_COMPLIANT

============================================================
Testing: Non-Compliant Policy (SecureTransport but wrong actions)
============================================================
Actions ['s3:GetObject'] do not cover EFS client actions
Found Deny with SecureTransport=false but does not apply to EFS client actions
No valid SecureTransport enforcement found for EFS client actions
Compliance: NON_COMPLIANT
Annotation: EFS file system policy does not enforce TLS (aws:SecureTransport) for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)
✅ PASSED - Expected NON_COMPLIANT, got NON_COMPLIANT

============================================================
Test Summary
============================================================
✅ PASSED: No Policy (Should be NON_COMPLIANT)
✅ PASSED: Compliant Policy with Deny + Action=* + SecureTransport=false
✅ PASSED: Compliant Policy with specific EFS client actions
✅ PASSED: Compliant Policy with elasticfilesystem:* action
✅ PASSED: Compliant Policy with elasticfilesystem:Client* pattern
✅ PASSED: Compliant Policy with BoolIfExists condition
✅ PASSED: Non-Compliant Policy (No SecureTransport enforcement)
✅ PASSED: Non-Compliant Policy (SecureTransport but wrong actions)

Total: 8/8 tests passed

🎉 All tests passed!
```

## Test Scenarios Explained

### Test 1: No Policy (NON_COMPLIANT)
**What it tests:** EFS file system without any resource policy attached

**Why NON_COMPLIANT:** Without a policy, TLS is not enforced

**Mock behavior:** Simulates `PolicyNotFound` exception from AWS API

---

### Test 2: Compliant Policy with Deny + Action=* + SecureTransport=false (COMPLIANT)
**What it tests:** EFS policy with proper TLS enforcement using `Bool` condition and wildcard action

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Action": "*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why COMPLIANT:** Denies all access (including EFS client actions) when SecureTransport is false

---

### Test 3: Compliant Policy with Specific EFS Client Actions (COMPLIANT)
**What it tests:** EFS policy that explicitly denies TLS-less access for EFS client operations

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Action": [
    "elasticfilesystem:ClientMount",
    "elasticfilesystem:ClientWrite",
    "elasticfilesystem:ClientRootAccess"
  ],
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why COMPLIANT:** Explicitly denies EFS client actions when TLS is not used

---

### Test 4: Compliant Policy with elasticfilesystem:* (COMPLIANT)
**What it tests:** EFS policy using EFS service wildcard action

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Action": "elasticfilesystem:*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why COMPLIANT:** `elasticfilesystem:*` covers all EFS actions including ClientMount, ClientWrite, ClientRootAccess

---

### Test 5: Compliant Policy with elasticfilesystem:Client* Pattern (COMPLIANT)
**What it tests:** EFS policy using pattern matching for client actions

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Action": "elasticfilesystem:Client*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why COMPLIANT:** Pattern `elasticfilesystem:Client*` matches all client operations

---

### Test 6: Compliant with BoolIfExists (COMPLIANT)
**What it tests:** Alternative compliant pattern using `BoolIfExists` condition

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Action": "*",
  "Condition": {
    "BoolIfExists": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why COMPLIANT:** `BoolIfExists` handles cases where SecureTransport key may not exist

---

### Test 7: Non-Compliant Policy - No SecureTransport (NON_COMPLIANT)
**What it tests:** EFS policy that allows access without TLS enforcement

**Policy structure:**
```json
{
  "Effect": "Allow",
  "Principal": "*",
  "Action": "*"
}
```

**Why NON_COMPLIANT:** No `aws:SecureTransport` condition, TLS not enforced

---

### Test 8: Non-Compliant Policy - Wrong Actions (NON_COMPLIANT)
**What it tests:** Policy has SecureTransport=false Deny but for wrong actions

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Action": "s3:GetObject",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why NON_COMPLIANT:** The Deny applies to S3 actions, not EFS client actions (ClientMount/ClientWrite/ClientRootAccess). This catches mis-scoped policies that appear compliant but don't actually protect EFS.

## Understanding the Test Code

### Mock Components

The test suite uses mocking to simulate AWS service responses without making actual API calls:

**boto3 Mocking:**
- boto3 is mocked at import time using `unittest.mock.MagicMock`
- This allows tests to run without boto3 installed locally
- The mock is injected into `sys.modules['boto3']` before importing lambda_function

**MockEFSClient:**
- Simulates `describe_file_system_policy()` API responses
- Returns different policies based on test scenario
- Raises `PolicyNotFound` exception for "no_policy" scenario
- Includes mock `exceptions` attribute with `PolicyNotFound` and `FileSystemNotFound`

**MockConfigClient:**
- Simulates `put_evaluations()` API call
- Captures evaluation results for verification
- No actual AWS Config API calls made

### Lambda Function Design for Testability

The lambda function uses **lazy initialization** for boto3 clients:
- Clients are created on first use via `get_efs_client()` and `get_config_client()`
- This allows tests to inject mocks before any AWS calls are made
- Prevents `NoRegionError` when running locally without AWS credentials

### Test Flow

```
1. Mock boto3 module before importing lambda_function
   ↓
2. Import and reload lambda_function module
   ↓
3. Patch get_efs_client() and get_config_client() with mocks
   ↓
4. Create AWS Config event (JSON format)
   ↓
5. Call lambda_handler(event, context)
   ↓
6. Capture evaluation result from MockConfigClient
   ↓
7. Compare actual vs expected compliance
   ↓
8. Print PASS/FAIL result
```

### EFS Client Action Validation

The Lambda function validates that Deny statements apply to EFS client actions:
- `elasticfilesystem:ClientMount` - Mount operations
- `elasticfilesystem:ClientWrite` - Write operations  
- `elasticfilesystem:ClientRootAccess` - Root access operations

Accepted action patterns:
- `*` (all actions)
- `elasticfilesystem:*` (all EFS actions)
- `elasticfilesystem:Client*` (all client actions)
- Explicit list of client actions

## Troubleshooting

### Issue: ModuleNotFoundError: No module named 'boto3'
**Note:** As of the latest update, boto3 is mocked in the test suite, so this error should not occur. If it does:

**Solution:**
```bash
# The test suite now mocks boto3, so this should work without boto3 installed
python3 test_lambda.py

# If you still need boto3 for other purposes:
source venv/bin/activate
pip install -r requirements.txt
```

### Issue: NoRegionError: You must specify a region
**Note:** This error occurred in older versions when boto3 clients were initialized at module load time.

**Solution:** This is now fixed. The Lambda function uses lazy initialization for boto3 clients, so they are only created when running in AWS Lambda (where region is automatically configured) or when mocks are injected for testing.

### Issue: ImportError: cannot import name 'lambda_function'
**Solution:**
```bash
# Ensure you're in the correct directory
pwd
# Should be: .../scripts/efs-tls-enforcement

# Verify lambda_function.py exists
ls -la lambda_function.py
```

### Issue: All tests fail with "Exception: ..."
**Solution:**
```bash
# Check Python version (must be 3.8+)
python3 --version

# Run with verbose output
python3 -v test_lambda.py
```

### Issue: Permission denied when running test_lambda.py
**Solution:**
```bash
# Make script executable
chmod +x test_lambda.py

# Run with python3 explicitly
python3 test_lambda.py
```

## Manual Testing with Custom Scenarios

### Create Custom Test Case

Edit `test_lambda.py` and add a new scenario:

```python
# Add to test_scenarios list in main()
{
    'name': 'Your Custom Test Name',
    'scenario': 'custom_scenario',
    'expected': 'COMPLIANT'  # or 'NON_COMPLIANT'
}
```

Then add the scenario to `MockEFSClient`:

```python
elif self.scenario == "custom_scenario":
    return {
        'Policy': json.dumps({
            # Your custom policy JSON here
        })
    }
```

## Validating Policy JSON

### Use Example Compliant Policy

The repository includes a reference policy:

```bash
# View example compliant policy
cat example_compliant_policy.json
```

This shows a production-ready EFS resource policy that:
1. ✅ Denies all access when `aws:SecureTransport: false`
2. ✅ Allows EFS operations when `aws:SecureTransport: true`

### Validate JSON Syntax

```bash
# Check if JSON is valid
python3 -m json.tool example_compliant_policy.json

# Should output formatted JSON without errors
```

## Integration with Terraform Deployment

### After Local Testing Succeeds

Once all tests pass locally:

1. **Commit changes** (if you modified the Lambda code):
   ```bash
   git add lambda_function.py test_lambda.py
   git commit -m "Update Lambda function logic"
   git push origin feature/ami-management-policy
   ```

2. **Deploy to dev environment**:
   ```bash
   cd ../../environments/dev
   terraform init
   terraform plan -target=module.efs_tls_enforcement_dev
   terraform apply -target=module.efs_tls_enforcement_dev
   ```

3. **Verify deployment in AWS**:
   - Check Lambda function in AWS Console
   - Check Config rule in AWS Config Console
   - Create test EFS with/without TLS policy
   - Verify compliance evaluations

## Best Practices

### ✅ Always Test Locally First
- Catches syntax errors before deployment
- Validates logic without AWS charges
- Faster iteration cycle

### ✅ Keep Test Suite Updated
- Add test cases for new scenarios discovered in production
- Update mocks when AWS API responses change
- Document expected behavior

### ✅ Use Virtual Environments
- Isolates dependencies from system Python
- Prevents version conflicts
- Easy cleanup (`rm -rf venv`)

### ✅ Version Control Test Data
- Commit test_lambda.py with code changes
- Include example policies in repository
- Document test scenarios in comments

## Clean Up

### Deactivate Virtual Environment
```bash
# When done testing
deactivate
```

### Remove Virtual Environment (Optional)
```bash
# If you want to completely remove venv
rm -rf venv
```

## Next Steps

After successful local testing:

1. ✅ All 8 tests pass locally
2. 📋 Review COMPLETE_DEPLOYMENT_GUIDE.md
3. 🚀 Deploy to dev environment with `terraform apply`
4. ✅ Validate in AWS Config console
5. 🎯 Deploy to production after dev validation

## Related Documentation

- **Lambda Function Code**: [lambda_function.py](scripts/efs-tls-enforcement/lambda_function.py)
- **Test Suite**: [test_lambda.py](scripts/efs-tls-enforcement/test_lambda.py)
- **Deployment Guide**: [COMPLETE_DEPLOYMENT_GUIDE.md](COMPLETE_DEPLOYMENT_GUIDE.md)
- **EFS Compliance Matrix**: [README_EFS_COMPLIANCE.md](README_EFS_COMPLIANCE.md)

---

**Questions or Issues?**
- Check troubleshooting section above
- Review test output for specific error messages
- Verify Python version and dependencies
