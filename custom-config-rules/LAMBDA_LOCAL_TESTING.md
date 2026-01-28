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

### Step 3: Install Dependencies
```bash
# Install required Python packages
pip install -r requirements.txt

# Verify installation
pip list | grep boto3
# Should show: boto3 1.26.0 or higher
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
Compliance: NON_COMPLIANT
Annotation: No file system policy found...
✅ PASSED - Expected NON_COMPLIANT, got NON_COMPLIANT

============================================================
Testing: Compliant Policy with Deny + SecureTransport=false
============================================================
Compliance: COMPLIANT
Annotation: EFS policy enforces TLS...
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Testing: Non-Compliant Policy (No SecureTransport enforcement)
============================================================
Compliance: NON_COMPLIANT
Annotation: EFS policy does not enforce TLS...
✅ PASSED - Expected NON_COMPLIANT, got NON_COMPLIANT

============================================================
Testing: Compliant Policy with BoolIfExists condition
============================================================
Compliance: COMPLIANT
Annotation: EFS policy enforces TLS...
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Test Summary
============================================================
✅ PASSED: No Policy (Should be NON_COMPLIANT)
✅ PASSED: Compliant Policy with Deny + SecureTransport=false
✅ PASSED: Non-Compliant Policy (No SecureTransport enforcement)
✅ PASSED: Compliant Policy with BoolIfExists condition

Total: 4/4 tests passed

🎉 All tests passed!
```

## Test Scenarios Explained

### Test 1: No Policy (NON_COMPLIANT)
**What it tests:** EFS file system without any resource policy attached

**Why NON_COMPLIANT:** Without a policy, TLS is not enforced

**Mock behavior:** Simulates `PolicyNotFound` exception from AWS API

---

### Test 2: Compliant Policy with Deny + SecureTransport=false (COMPLIANT)
**What it tests:** EFS policy with proper TLS enforcement using `Bool` condition

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why COMPLIANT:** Denies all access when SecureTransport is false (enforces TLS)

---

### Test 3: Non-Compliant Policy (NON_COMPLIANT)
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

### Test 4: Compliant with BoolIfExists (COMPLIANT)
**What it tests:** Alternative compliant pattern using `BoolIfExists` condition

**Policy structure:**
```json
{
  "Effect": "Deny",
  "Condition": {
    "BoolIfExists": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Why COMPLIANT:** Denies access when SecureTransport is false (enforces TLS)

## Understanding the Test Code

### Mock Components

The test suite uses mocking to simulate AWS service responses without making actual API calls:

**MockEFSClient:**
- Simulates `describe_file_system_policy()` API responses
- Returns different policies based on test scenario
- Raises `PolicyNotFound` exception for "no_policy" scenario

**MockConfigClient:**
- Simulates `put_evaluations()` API call
- Captures evaluation results for verification
- No actual AWS Config API calls made

### Test Flow

```
1. Import lambda_function module
   ↓
2. Replace boto3 clients with mock objects
   ↓
3. Create AWS Config event (JSON format)
   ↓
4. Call lambda_handler(event, context)
   ↓
5. Capture evaluation result from mock
   ↓
6. Compare actual vs expected compliance
   ↓
7. Print PASS/FAIL result
```

## Troubleshooting

### Issue: ModuleNotFoundError: No module named 'boto3'
**Solution:**
```bash
# Ensure virtual environment is activated
source venv/bin/activate

# Reinstall dependencies
pip install -r requirements.txt
```

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

1. ✅ All 4 tests pass locally
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
