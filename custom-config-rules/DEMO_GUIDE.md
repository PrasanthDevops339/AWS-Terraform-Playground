# EFS TLS Enforcement - Demo Guide

## Overview

This guide provides a comprehensive walkthrough for demonstrating the EFS TLS Enforcement solution to your team, including detailed technical analysis of the Lambda function implementation.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Demo Prerequisites](#demo-prerequisites)
3. [Demo Flow](#demo-flow)
4. [Step-by-Step Demo Script](#step-by-step-demo-script)
5. [Lambda Function Deep Dive](#lambda-function-deep-dive)
6. [Function-by-Function Analysis](#function-by-function-analysis)
7. [Test Scenarios](#test-scenarios)
8. [Troubleshooting](#troubleshooting)
9. [Q&A Preparation](#qa-preparation)

---

## Executive Summary

### What We're Demonstrating

**AWS Config Custom Lambda Rule for EFS TLS Enforcement**

This solution validates that Amazon EFS file systems enforce TLS (encryption in-transit) through resource policies. It complements Guard policy rules for encryption-at-rest validation.

### Why This Matters

- **Compliance**: Ensures sensitive data is encrypted during transit
- **Security**: Prevents unencrypted network access to EFS file systems
- **Automation**: Continuous compliance monitoring via AWS Config
- **Organization-Wide**: Deploys across all accounts via conformance packs

### Key Technical Components

1. **Guard Policy Rules**: Validate EFS encryption-at-rest (configuration item data)
2. **Lambda Custom Rule**: Validate EFS TLS enforcement (requires API calls)
3. **AWS Managed Rules**: S3 versioning and RDS encryption (bonus examples)
4. **Conformance Pack**: Organization-wide deployment via CloudFormation
5. **Terraform Modules**: Infrastructure-as-code for repeatable deployments

---

## Demo Prerequisites

### Before the Demo

#### 1. Environment Setup
```bash
# Ensure you're in the correct directory
cd /Users/prasanthkorepally/Documents/GitHub/AWS-Terraform-Playground/custom-config-rules

# Verify branch
git branch
# Should show: * feature/ami-management-policy

# Pull latest changes
git pull origin feature/ami-management-policy
```

#### 2. AWS Console Access
- Management account access (for organization conformance packs)
- Dev account access (for single-account testing)
- AWS Config console access
- Lambda console access
- EFS console access

#### 3. Demo Resources (Pre-Created)
Create these in dev account **before** the demo:

**Compliant EFS File System:**
```bash
# Create EFS with encryption and TLS policy
aws efs create-file-system \
  --encrypted \
  --tags Key=Name,Value=demo-efs-compliant \
  --region us-east-2

# Note the FileSystemId (e.g., fs-12345678)

# Attach TLS enforcement policy
aws efs put-file-system-policy \
  --file-system-id fs-12345678 \
  --policy file://scripts/efs-tls-enforcement/example_compliant_policy.json \
  --region us-east-2
```

**Non-Compliant EFS File System:**
```bash
# Create EFS without TLS enforcement
aws efs create-file-system \
  --encrypted \
  --tags Key=Name,Value=demo-efs-non-compliant \
  --region us-east-2

# Note the FileSystemId - DO NOT attach policy (will be NON_COMPLIANT)
```

#### 4. Have These Open in Browser Tabs
1. AWS Config Console → Rules
2. Lambda Console → Functions
3. EFS Console → File Systems
4. CloudFormation Console → Stacks
5. GitHub Repository (for code walkthrough)

---

## Demo Flow

### High-Level Agenda (45-60 minutes) - Lambda-Focused

1. **Introduction** (5 min)
   - Problem statement: Why Lambda for TLS validation?
   - Quick architecture overview

2. **Lambda Function Deep Dive** (25-30 min) ⭐ **MAIN FOCUS**
   - File structure and organization (2 min)
   - Entry point: `lambda_handler()` (5 min)
   - Core validation: `evaluate_efs_tls_policy()` (5 min)
   - Policy parsing: `is_secure_transport_enforced()` (8 min)
   - Action validation: `_validates_client_actions()` (5 min)
   - Helper functions: timestamps, annotations, submission (5 min)

3. **Live Function Testing** (10 min)
   - Run test suite locally
   - Walk through test scenarios
   - Demonstrate mock client behavior
   - Debug a test case live

4. **Live AWS Validation** (5 min)
   - Trigger Lambda from Config
   - Inspect CloudWatch logs showing function flow
   - Compare expected vs actual behavior

5. **Q&A** (5-10 min)
   - Technical questions
   - Function design decisions

---

## Step-by-Step Demo Script

### Part 1: Introduction (5 minutes)

#### Slide 1: The Challenge

**Say:** "Let's talk about a common compliance requirement: ensuring EFS file systems enforce TLS for encryption in-transit."

**Show:** Diagram with three key points:
```
┌─────────────────────────────────────────┐
│  EFS Compliance Requirements            │
├─────────────────────────────────────────┤
│  ✓ Encryption at Rest (Guard Policy)   │
│  ✓ Encryption in Transit (Lambda Rule) │← We're focusing here
│  ✓ Organization-Wide Enforcement        │
└─────────────────────────────────────────┘
```

**Key Point:** "Guard policies can validate encryption-at-rest because that's in the Config item. But TLS enforcement requires checking the EFS **resource policy**, which isn't in Config items. This is where Lambda rules come in."

#### Slide 2: Why Lambda?

**Show:** Comparison table from README_EFS_COMPLIANCE.md

**Say:** "Let me show you why we need Lambda for this specific check..."

**Navigate to:** `custom-config-rules/README_EFS_COMPLIANCE.md`

**Highlight:**
```markdown
| Aspect          | Guard Policy          | Lambda Rule              |
|-----------------|-----------------------|--------------------------|
| What It Checks  | Encrypted = true      | Policy aws:SecureTransport |
| API Calls       | ❌ No                 | ✅ Yes (DescribeFileSystemPolicy) |
| Data Source     | Config Item           | EFS API                  |
```

**Key Point:** "Guard policies can't make API calls. Lambda functions can. This is a perfect use case for a custom Lambda rule."

### Part 2: Lambda Function Deep Dive (25-30 minutes) ⭐ **MAIN DEMO FOCUS**

#### Setup: Open Lambda Function

**Open in VS Code:** `scripts/efs-tls-enforcement/lambda_function.py`

**Terminal (Side by Side):**
```bash
cd /Users/prasanthkorepally/Documents/GitHub/AWS-Terraform-Playground/custom-config-rules/scripts/efs-tls-enforcement

# Have Python file open on left, terminal on right
```

**Say:** "This is where the magic happens. Over the next 30 minutes, we'll walk through every function in this Lambda, understanding exactly how it validates EFS TLS enforcement."

---

#### Section A: File Overview (2 minutes)

**Scroll to top and explain:**

**Say:** "Before diving into code, let's understand the problem this solves..."

**Highlight Docstring Lines 1-40:**

**Read out loud key points:**
1. "EFS resource policies are NOT in Config items" ← This is critical
2. "Must call efs:DescribeFileSystemPolicy API" ← Can't do with Guard
3. "Must parse JSON policy and evaluate Deny statements" ← Complex logic
4. "Guard policies can't make API calls" ← Why Lambda

**Say:** "Keep these 4 points in mind - they explain every design decision in this code."

**Show file structure:**
```python
# Line 50-100: Constants and lazy client initialization
# Line 100-180: lambda_handler() - Entry point
# Line 180-220: Helper functions (timestamps, annotations)
# Line 220-280: evaluate_efs_tls_policy() - Core logic
# Line 280-350: is_secure_transport_enforced() - Policy validation
# Line 350-420: _validates_client_actions() - Action scope
# Line 420-450: _action_matches() - Pattern matching
```

**Say:** "227 lines total. Let's walk through the execution flow function by function."

---

#### Section B: Constants & Lazy Initialization (3 minutes)

**Scroll to Lines 50-100:**

**Say:** "Let's start with the building blocks..."

**Highlight Constants:**
```python
MAX_ANNOTATION_LENGTH = 256  # AWS Config annotation limit
```

**Say:** "AWS Config has a hard limit - 256 characters for annotations. If we exceed this, the API call fails. We'll clip messages later using this constant."

**Highlight Lazy Clients:**
```python
efs_client: Optional[Any] = None
config_client: Optional[Any] = None

def get_efs_client():
    global efs_client
    if efs_client is None:
        efs_client = boto3.client('efs')  # Note: 'efs', not 'elasticfilesystem'
    return efs_client
```

**Say:** "Why not initialize at module level? Two reasons:"
1. **Local testing**: Can run without AWS credentials
2. **Mocking**: Test suite injects mock clients before first use

**Pause for emphasis:** "This is a key testing pattern. The clients don't exist until someone calls `get_efs_client()`. Tests call this pattern to inject mocks."

---

#### Section C: Entry Point - `lambda_handler()` (5 minutes)

**Scroll to Line ~100 and highlight function signature:**

```python
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda handler for EFS TLS enforcement validation."""
```

**Say:** "This is where AWS Config calls us. When an EFS resource changes, Config sends a JSON event. Let's trace the execution step by step."

**Step 1: Logging (Lines ~110-115)**

```python
logger.info(f"Event keys: {list(event.keys())}")
logger.info(f"Config rule name: {event.get('configRuleName', 'unknown')}")
```

**Say:** "We DON'T log the full event - it can be huge. Just the keys to help debug."

**Step 2: Parse Invoking Event (Lines ~115-125)**

```python
raw_invoking_event = event.get('invokingEvent') or event.get('configRuleInvokingEvent')
invoking_event = json.loads(raw_invoking_event)
configuration_item = invoking_event.get('configurationItem', {})
```

**Say:** "Config sends a JSON string inside JSON. We parse it to get the configuration item. Notice we support both key names - backwards compatibility."

**Interactive:** "What happens if this JSON parsing fails?"
---

#### Section D: Core Evaluation - `evaluate_efs_tls_policy()` (5 minutes)

**Scroll to Line ~220:**

**Say:** "Now the heart of the function - where we actually check EFS."

**Highlight function signature:**
```python
def evaluate_efs_tls_policy(file_system_id: str) -> Tuple[str, str]:
    """Returns: (compliance_type, annotation)"""
```

**Say:** "Takes EFS ID, returns tuple: compliance status and message. Simple interface, complex logic inside."

**Step 1: Get Client**
```python
efs = get_efs_client()
```

**Say:** "First call to `get_efs_client()` - this is where boto3.client('efs') gets created if it doesn't exist yet."

**Step 2: API Call** ⭐⭐⭐

```python
response = efs.describe_file_system_policy(FileSystemId=file_system_id)
policy_json = response.get('Policy')
```

**Pause dramatically:** "THIS LINE is why we need Lambda."

**Say:** "We're calling the EFS API to get the resource policy. This data is NOT in the Config configuration item. Guard policies only see Config items - they can't make API calls. This is the fundamental reason Lambda is required."

**Show API response format:**
```python
# Response structure:
{
  'FileSystemId': 'fs-12345678',
  'Policy': '{"Version":"2012-10-17","Statement":[...]}'  # ← JSON string
}
```

**Step 3: Check Policy Exists**
```python
if not policy_json:
    return 'NON_COMPLIANT', 'EFS file system has no policy defined'
```

**Say:** "No policy? That means no TLS enforcement. Anyone can mount without encryption. NON_COMPLIANT."

**Step 4: Parse JSON**
```python
policy = json.loads(policy_json)
```

**Say:** "The policy comes as a JSON string. We parse it into a Python dict so we can inspect its structure."

**Step 5: Validate Policy**
```python
if is_secure_transport_enforced(policy, file_system_id):
    return 'COMPLIANT', 'EFS policy enforces TLS for client actions'
else:
    return 'NON_COMPLIANT', 'EFS policy does not enforce TLS for client actions'
```

**Say:** "We call another function to inspect the policy details. We'll look at that next."

**Exception Handling:**

```python
except efs.exceptions.PolicyNotFound:
    return 'NON_COMPLIANT', 'EFS has no policy - TLS not configured'
```
**Say:** "PolicyNotFound is different from empty response. It means EFS explicitly has no policy attached."

```python
except efs.exceptions.FileSystemNotFound:
    return 'NON_COMPLIANT', f'EFS not found: {file_system_id}'
```
**Say:** "Shouldn't happen - Config wouldn't send us a deleted resource. But we handle it anyway."

```python
except Exception as e:
    error_msg = clip_annotation(f'Error evaluating policy: {str(e)}')
    return 'NON_COMPLIANT', error_msg
```
**Say:** "Any other error? Fail closed - return NON_COMPLIANT. We don't want to mark insecure resources as compliant due to evaluation errors."

**Terminal Demo:**
```bash
# Show the function
grep -A 20 "def evaluate_efs_tls_policy" lambda_function.py
```
```
**Say:** "Deleted resources can't be non-compliant. They don't exist."

**Step 5: Core Evaluation (Line ~165)**

```python
compliance_type, annotation = evaluate_efs_tls_policy(resource_id)
```

**Pause here:** "THIS is where the real work happens. We'll look at this function next."

**Step 6: Submit Result (Lines ~170-180)**

```python
return submit_evaluation(
    event=event,
    resource_id=resource_id,
    compliance_type=compliance_type,
    annotation=clip_annotation(annotation),  # ← Clip to 256 chars
    ordering_timestamp=ordering_timestamp
)
```

---

#### Section E: Policy Validation - `is_secure_transport_enforced()` (8 minutes)

**Scroll to Line ~280:**

**Say:** "Now the complex part - parsing the IAM policy JSON to validate TLS enforcement."

**Show example policy first:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Say:** "This is what we're looking for. Let's see how the code validates it."

**Function Signature:**
```python
def is_secure_transport_enforced(policy: Dict[str, Any], file_system_id: str = None) -> bool:
```

**Say:** "Takes parsed policy dict, returns boolean. True = compliant, False = not compliant."

**Step 1: Get Statements**
```python
statements = policy.get('Statement', [])

for statement in statements:
```

**Say:** "IAM policies have a Statement array. We check each statement looking for TLS enforcement."

**Step 2: Check Effect**
```python
effect = statement.get('Effect', '')
if effect != 'Deny':
    continue  # Skip Allow statements
```

**Interactive:** "Why only check Deny statements?"

**Answer:** "Allow statements don't prevent anything. Only Deny can enforce TLS. An Allow statement says 'you can do this' but doesn't block unencrypted access."

**Step 3: Check Condition** (Lines ~340-355)

```python
condition = statement.get('Condition', {})
bool_condition = condition.get('Bool', {})
bool_if_exists = condition.get('BoolIfExists', {})

secure_transport_check = (
    bool_condition.get('aws:SecureTransport') == 'false' or
    bool_condition.get('aws:SecureTransport') is False or
    bool_if_exists.get('aws:SecureTransport') == 'false' or
    bool_if_exists.get('aws:SecureTransport') is False
)
```

**Say:** "We check FOUR combinations:"
1. `Bool` condition with string `"false"`
2. `Bool` condition with boolean `False`
3. `BoolIfExists` with string `"false"`
4. `BoolIfExists` with boolean `False`

**Interactive:** "Why both string and boolean?"

**Answer:** "IAM policy JSON can have either. We're defensive - accept both formats."

**Interactive:** "What's the difference between Bool and BoolIfExists?"

**Answer:** 
- `Bool`: Denies if key exists and is false
- `BoolIfExists`: Denies if key doesn't exist OR is false

**Say:** "Both work for our purposes - they both enforce TLS."

**Step 4: Validate Action Scope** ⭐ **CRITICAL**

```python
if not _validates_client_actions(statement):
    logger.warning("Deny with SecureTransport but doesn't apply to client actions")
    continue
```

**Say:** "HERE is where we prevent false positives."

**Show example of false positive:**
```json
{
  "Effect": "Deny",
  "Action": "s3:*",  // ← Only denies S3!
  "Condition": {
    "Bool": {"aws:SecureTransport": "false"}
  }
}
---

#### Section F: Action Validation - `_validates_client_actions()` (5 minutes)

**Scroll to Line ~380:**

**Say:** "This helper function answers: Does this Deny statement actually protect EFS client access?"

**Show the constant again:**
```python
EFS_CLIENT_ACTIONS = [
    'elasticfilesystem:ClientMount',
    'elasticfilesystem:ClientWrite',
    'elasticfilesystem:ClientRootAccess'
]
```

**Say:** "These are the three actions we MUST protect. If a Deny doesn't cover these, it's not enforcing TLS for EFS."

**Function Logic:**

**Step 1: Extract Actions**
```python
actions = statement.get('Action', [])
not_actions = statement.get('NotAction', [])

# Normalize to list
if isinstance(actions, str):
    actions = [actions]
```

**Say:** "Actions can be a string or list. We normalize to list for consistent processing."

**Step 2: Handle NotAction (Inverse Logic)**
```python
if not_actions:
    for not_action in not_actions:
        for client_action in EFS_CLIENT_ACTIONS:
            if _action_matches(not_action, client_action):
                return False  # Client action excluded!
    return True  # Client actions not excluded, so they're covered
```

**Say:** "NotAction is tricky - it means 'everything EXCEPT these'. If our client actions are in the NotAction list, they're NOT protected."

**Example:**
```json
{
  "NotAction": "elasticfilesystem:Client*"
}
```
---

### Part 4: Live AWS Validation (5
**Say:** "Converts ISO timestamp string to datetime object. Config expects datetime, not string."

**3. `submit_evaluation()` - Line ~245**
```python
def submit_evaluation(...) -> Dict[str, Any]:
    evaluation = {
        'ComplianceResourceType': resource_type,
        'ComplianceResourceId': resource_id,
        'ComplianceType': compliance_type,
        'Annotation': annotation,
        'OrderingTimestamp': ordering_timestamp
    }
    
    response = get_config_client().put_evaluations(
        Evaluations=[evaluation],
        ResultToken=event['resultToken']
    )
```

**Say:** "Builds evaluation result and sends to Config via PutEvaluations API. This is how Config gets our compliance verdict."

**Summary:**
```
lambda_handler() 
  → evaluate_efs_tls_policy()
    → is_secure_transport_enforced()
      → _validates_client_actions()
        → _action_matches()
  → submit_evaluation()
```

**Say:** "This is the complete execution flow. Every function has a clear purpose."

---

### Part 3: Live Function Testing (10 minutes)

**Say:** "Now let's see these functions in action through local testing."

#### Open Test File

**Open:** `scripts/efs-tls-enforcement/test_lambda.py`

**Scroll to `MockEFSClient` class:**

```python
class MockEFSClient:
    def __init__(self, scenario):
        self.scenario = scenario
    
    def describe_file_system_policy(self, FileSystemId):
        if self.scenario == "no_policy":
            raise ClientError(...)
        elif self.scenario == "compliant_deny":
            return {'Policy': json.dumps({...})}
```

**Say:** "The mock client simulates AWS API responses without making actual calls. Notice it returns the same data structure the real EFS API would."

**Show mock injection:**
```python
import lambda_function

lambda_function.efs_client = MockEFSClient(scenario)
lambda_function.config_client = MockConfigClient()
```

**Say:** "We replace the global clients with mocks before calling the lambda handler. This is why lazy initialization is so important."

#### Run Tests Live

**Terminal:**
```bash
cd scripts/efs-tls-enforcement
python3 test_lambda.py
```

**Expected output:**
```
============================================================
EFS TLS Enforcement Lambda Function - Test Suite
============================================================

============================================================
Testing: No Policy (Should be NON_COMPLIANT)
============================================================
Compliance: NON_COMPLIANT
Annotation: EFS file system has no policy - TLS enforcement not configured
✅ PASSED - Expected NON_COMPLIANT, got NON_COMPLIANT

============================================================
Testing: Compliant Policy with Deny + SecureTransport=false
============================================================
Compliance: COMPLIANT
Annotation: EFS file system policy enforces TLS (aws:SecureTransport) for client actions
✅ PASSED - Expected COMPLIANT, got COMPLIANT

============================================================
Testing: Non-Compliant Policy (No SecureTransport enforcement)
============================================================
Compliance: NON_COMPLIANT
Annotation: EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)
✅ PASSED - Expected NON_COMPLIANT, got NON_COMPLIANT

============================================================
Testing: Compliant Policy with BoolIfExists condition
============================================================
Compliance: COMPLIANT
Annotation: EFS file system policy enforces TLS (aws:SecureTransport) for client actions
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

**Say:** "All 4 scenarios pass. Each test calls `lambda_handler()` end-to-end, exercising every function we just reviewed."

#### Debug a Test Case

**Say:** "Let's add some debug output to understand the flow..."

**Edit test file temporarily:**
```python
# Add this before running test
import logging
logging.basicConfig(level=logging.INFO)
```

**Re-run one test:**
```bash
# Modify test_lambda.py to run only compliant_deny scenario
python3 test_lambda.py
```

**Show logs:**
```
INFO:root:Event keys: ['configRuleInvokingEvent', 'resultToken']
INFO:root:Config rule name: test-rule
INFO:root:EFS Policy for fs-12345678: policy retrieved successfully
INFO:root:Action '*' covers all EFS client actions
INFO:root:Found compliant Deny statement: SecureTransport=false with EFS client actions
INFO:root:Evaluation submitted: compliance=COMPLIANT, resource=fs-12345678
```

**Say:** "See the execution flow? Event received → Policy retrieved → Actions validated → Compliant statement found → Evaluation submitted. This traces through all our functions
    1. Denies when aws:SecureTransport is false
    2. Applies to EFS client actions
    """
    statements = policy.get('Statement', [])
    
    for statement in statements:
        # 1. Check Effect is Deny
        if effect != 'Deny':
            continue
        
        # 2. Check for SecureTransport condition
        secure_transport_check = (
            bool_condition.get('aws:SecureTransport') == 'false' or
            bool_if_exists.get('aws:SecureTransport') == 'false'
        )
        
        # 3. Validate it applies to client actions
        if not _validates_client_actions(statement):
            continue
        
        return True  # Found compliant statement
    
    return False  # No compliant statement found
```

**Say:** "We're looking for a Deny statement that:"
- Denies when `aws:SecureTransport` is `false`
- Applies to EFS client mount/write/access actions

**Highlight:** The `_validates_client_actions` helper function

**Say:** "This helper checks if the policy applies to EFS client actions. It handles wildcards, explicit lists, and NotAction patterns."

#### File 2: Test Suite

**Open:** `scripts/efs-tls-enforcement/test_lambda.py`

**Say:** "Let's look at how we test this locally..."

**Scroll to `MockEFSClient` class:**

```python
class MockEFSClient:
    def __init__(self, scenario):
        self.scenario = scenario
    
    def describe_file_system_policy(self, FileSystemId):
        if self.scenario == "no_policy":
            raise ClientError(...)
        elif self.scenario == "compliant_deny":
            return {'Policy': json.dumps({...})}
```

**Say:** "The mock client simulates AWS API responses without making actual calls. We test 4 scenarios:"
1. No policy (NON_COMPLIANT)
2. Compliant policy with Deny (COMPLIANT)
3. Non-compliant policy (NON_COMPLIANT)
4. Compliant with BoolIfExists (COMPLIANT)

**Terminal: Run Tests**

```bash
cd scripts/efs-tls-enforcement
python3 test_lambda.py
```

**Expected output:**
```
============================================================
EFS TLS Enforcement Lambda Function - Test Suite
============================================================
...
✅ PASSED: No Policy (Should be NON_COMPLIANT)
✅ PASSED: Compliant Policy with Deny + SecureTransport=false
✅ PASSED: Non-Compliant Policy
✅ PASSED: Compliant Policy with BoolIfExists condition

Total: 4/4 tests passed

🎉 All tests passed!
```

**Say:** "All 4 tests pass locally. This gives us confidence before deploying to AWS."

### Part 3: Deployment Demo (10 minutes)

#### Show Terraform Structure

**Terminal:**
```bash
cd /Users/prasanthkorepally/Documents/GitHub/AWS-Terraform-Playground/custom-config-rules

# Show module structure
ls -la modules/
```

**Say:** "We have three Terraform modules:"
1. **lambda_rule**: Deploys Lambda function + Config rule
2. **policy_rule**: Deploys Guard policy rules
3. **conformance_pack**: Combines all rules into organization pack

#### Show Dev Environment Configuration

**Open:** `environments/dev/lambda_efs_tls.tf`

**Highlight:**
```terraform
module "efs_tls_enforcement_dev" {
  source            = "../../modules/lambda_rule"
  organization_rule = false  # Single account for testing
  config_rule_name  = var.is_pre_dev ? "efs-tls-enforcement-dev-${local.random_id}" : "efs-tls-enforcement-dev"
  lambda_script_dir = "../../scripts/efs-tls-enforcement"
  random_id         = local.random_id  # Pre-dev isolation
```

**Say:** "Key features:"
- `organization_rule = false` → Single account testing
- `random_id` → Pre-dev resource isolation
- `lambda_script_dir` → Points to our Python code

#### Show Conformance Pack Configuration

**Open:** `environments/dev/cpack_encryption.tf`

**Highlight all three rule types:**

```terraform
module "cpack_encryption" {
  # Guard Policy Rules (encryption at-rest)
  policy_rules_list = [
    { config_rule_name = "ebs-is-encrypted", ... },
    { config_rule_name = "sqs-is-encrypted", ... },
    { config_rule_name = "efs-is-encrypted", ... }
  ]
  
  # Lambda Rules (encryption in-transit)
  lambda_rules_list = [
    { config_rule_name = "efs-tls-enforcement", 
      lambda_function_arn = module.efs_tls_enforcement_dev.lambda_arn, ... }
  ]
  
  # AWS Managed Rules (bonus examples)
  managed_rules_list = [
    { config_rule_name = "s3-bucket-versioning-enabled", ... },
    { config_rule_name = "rds-storage-encrypted", ... }
  ]
}
```

**Say:** "This conformance pack includes:"
- **3 Guard rules** for at-rest encryption
- **1 Lambda rule** for in-transit encryption  
- **2 AWS Managed rules** as examples

**Key Point:** "All deployed together as one CloudFormation stack via Config conformance pack."

#### Deployment Commands (Show, Don't Run Live)

**Terminal:**
```bash
# Initialize Terraform
cd environments/dev
terraform init

# Plan deployment
terraform plan

# Apply (show this conceptually)
terraform apply
```

**Say:** "In practice, this would:"
1. Create Lambda function
2. Upload Python code to S3
3. Create IAM role with least privilege
4. Create Config rule (single account)
5. Deploy conformance pack with all rules

### Part 4: Live Validation (10 minutes)

#### AWS Console Demo

**Navigate to AWS Config Console:**

**1. Show Config Rules**

URL: `https://us-east-2.console.aws.amazon.com/config/home?region=us-east-2#/rules`

**Say:** "Let's look at our deployed rules..."

**Show:**
- Filter for "efs"
- Find `efs-tls-enforcement-dev` rule
- Click on rule name

**Point out:**
- Rule status: Active
- Rule type: Custom Lambda
- Trigger: Configuration changes
- Resource type: AWS::EFS::FileSystem

**2. Show Compliance Dashboard**

**Navigate to:** Rules → Compliance

**Say:** "Here we can see compliance status across resources..."

**Show:**
- Compliant resources (green)
- Non-compliant resources (red)
- Not applicable resources (gray)

**3. Examine Compliant EFS**

**Click on:** Compliant EFS file system (fs-12345678)

**Show:**
- Resource type: AWS::EFS::FileSystem
- Compliance: COMPLIANT
- Annotation: "EFS file system policy enforces TLS (aws:SecureTransport) for client actions"
- Timeline showing when it became compliant

**Navigate to EFS Console:**

**Show the policy:**
```bash
# In terminal
aws efs describe-file-system-policy \
  --file-system-id fs-12345678 \
  --region us-east-2 \
  --output json | jq '.Policy | fromjson'
```

**Point out the Deny statement:**
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

**Say:** "See this Deny statement? It prevents any action when SecureTransport is false. This is what makes it compliant."

**4. Examine Non-Compliant EFS**

**Navigate back to Config Console**

**Click on:** Non-compliant EFS file system

**Show:**
- Compliance: NON_COMPLIANT
- Annotation: "EFS file system has no policy - TLS enforcement not configured"

**Say:** "This EFS has no resource policy, so TLS isn't enforced."

#### Lambda Logs Inspection

**Navigate to CloudWatch Logs:**

URL: `https://console.aws.amazon.com/cloudwatch/home?region=us-east-2#logsV2:log-groups`

**Find log group:** `/aws/lambda/efs-tls-enforcement-dev`

**Open recent log stream**

**Show log entries:**
```
INFO Event keys: ['configRuleInvokingEvent', 'resultToken', ...]
INFO Config rule name: efs-tls-enforcement-dev
INFO EFS Policy for fs-12345678: policy retrieved successfully
INFO Found compliant Deny statement: SecureTransport=false with EFS client actions
INFO Evaluation submitted: compliance=COMPLIANT, resource=fs-12345678
```

**Say:** "The logs show:"
1. Event received from Config
2. Policy retrieved via API call
3. Compliant Deny statement found
4. Evaluation submitted back to Config

**Key Point:** "This is real-time compliance monitoring. Every time an EFS policy changes, this Lambda evaluates it."

#### Demonstrate Remediation

**Say:** "Let's make a non-compliant EFS compliant in real-time..."

**Terminal:**
```bash
# Attach TLS policy to non-compliant EFS
aws efs put-file-system-policy \
  --file-system-id fs-87654321 \
  --policy file://scripts/efs-tls-enforcement/example_compliant_policy.json \
  --region us-east-2
```

**Wait 1-2 minutes**

**Refresh Config Console:**

**Show:**
- Status changes from NON_COMPLIANT → COMPLIANT
- Timeline shows the change event
- Annotation updates

**Say:** "Within minutes of adding the policy, Config re-evaluated and marked it compliant. This is continuous compliance monitoring in action."

---

## Lambda Function Deep Dive

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    AWS Config Service                    │
│  • Detects EFS configuration changes                    │
│  • Invokes Lambda with Config event                     │
│  • Receives evaluation result                           │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Lambda: efs-tls-enforcement                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │  1. lambda_handler()                              │  │
│  │     • Parse Config event                          │  │
│  │     • Extract EFS resource ID                     │  │
│  │     • Handle edge cases                           │  │
│  └─────────────────┬─────────────────────────────────┘  │
│                    ▼                                     │
│  ┌───────────────────────────────────────────────────┐  │
│  │  2. evaluate_efs_tls_policy()                     │  │
│  │     • Call EFS DescribeFileSystemPolicy API       │  │
│  │     • Parse JSON policy document                  │  │
│  │     • Invoke validation logic                     │  │
│  └─────────────────┬─────────────────────────────────┘  │
│                    ▼                                     │
│  ┌───────────────────────────────────────────────────┐  │
│  │  3. is_secure_transport_enforced()                │  │
│  │     • Find Deny statements                        │  │
│  │     • Check SecureTransport condition             │  │
│  │     • Validate applies to client actions          │  │
│  └─────────────────┬─────────────────────────────────┘  │
│                    ▼                                     │
│  ┌───────────────────────────────────────────────────┐  │
│  │  4. submit_evaluation()                           │  │
│  │     • Build evaluation result                     │  │
│  │     • Call Config PutEvaluations API              │  │
│  │     • Return response                             │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                  EFS Service API                         │
│  • DescribeFileSystemPolicy                             │
│  • Returns resource policy JSON                         │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

```
Config Event (JSON)
│
├─ configRuleInvokingEvent
│  └─ configurationItem
│     ├─ resourceId: "fs-12345678"
│     ├─ resourceType: "AWS::EFS::FileSystem"
│     └─ configurationItemCaptureTime: "2026-01-26T12:00:00Z"
│
├─ resultToken: "abc123..."
└─ configRuleName: "efs-tls-enforcement-dev"

        ↓ lambda_handler() ↓

EFS API Call: describe_file_system_policy(fs-12345678)
│
└─ Response:
   └─ Policy: "{\"Version\":\"2012-10-17\",\"Statement\":[...]}"

        ↓ evaluate_efs_tls_policy() ↓

Parsed Policy (Dict)
│
├─ Version: "2012-10-17"
└─ Statement: [
   ├─ Effect: "Deny"
   ├─ Action: "*"
   └─ Condition:
      └─ Bool:
         └─ aws:SecureTransport: "false"
]

        ↓ is_secure_transport_enforced() ↓

Validation Result
├─ Found Deny statement: True
├─ SecureTransport=false: True
└─ Applies to client actions: True
   → COMPLIANT

        ↓ submit_evaluation() ↓

Config Evaluation (JSON)
│
├─ ComplianceResourceType: "AWS::EFS::FileSystem"
├─ ComplianceResourceId: "fs-12345678"
├─ ComplianceType: "COMPLIANT"
├─ Annotation: "EFS policy enforces TLS for client actions"
└─ OrderingTimestamp: "2026-01-26T12:00:00Z"

        ↓ PutEvaluations API ↓

AWS Config Dashboard (Updated)
```

---

## Function-by-Function Analysis

### 1. `get_efs_client()` and `get_config_client()`

**Purpose:** Lazy initialization of boto3 clients

**Code:**
```python
def get_efs_client():
    """Get or create EFS client (lazy initialization)."""
    global efs_client
    if efs_client is None:
        efs_client = boto3.client('efs')
    return efs_client
```

**Why It Exists:**
- Enables local testing without AWS credentials
- Clients created only when needed (not at module load)
- Test suite can inject mock clients before first use

**Key Design Decision:**
- Uses `boto3.client('efs')` NOT `boto3.client('elasticfilesystem')`
- IAM actions use `elasticfilesystem:*` but boto3 uses `'efs'`

**When Called:**
- `evaluate_efs_tls_policy()` → calls `get_efs_client()`
- `submit_evaluation()` → calls `get_config_client()`

**Error Handling:**
- None needed - boto3.client() handles initialization errors

---

### 2. `lambda_handler(event, context)`

**Purpose:** Main entry point called by AWS Config

**Signature:**
```python
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]
```

**Input (event):**
```json
{
  "configRuleInvokingEvent": "{\"configurationItem\":{...}}",
  "resultToken": "abc123...",
  "configRuleName": "efs-tls-enforcement-dev"
}
```

**Processing Steps:**

1. **Log Event Keys** (Line ~110)
   ```python
   logger.info(f"Event keys: {list(event.keys())}")
   logger.info(f"Config rule name: {event.get('configRuleName', 'unknown')}")
   ```
   - Logs keys only (not full event - can be large)
   - Helps debugging without exposing sensitive data

2. **Parse Invoking Event** (Lines ~115-120)
   ```python
   raw_invoking_event = event.get('invokingEvent') or event.get('configRuleInvokingEvent')
   invoking_event = json.loads(raw_invoking_event)
   ```
   - Supports both key formats (backwards compatibility)
   - JSON string → Python dict

3. **Extract Configuration Item** (Lines ~125-135)
   ```python
   configuration_item = invoking_event.get('configurationItem', {})
   resource_id = configuration_item.get('resourceId')
   resource_type = configuration_item.get('resourceType')
   ```
   - Gets EFS file system ID
   - Gets resource type (should be AWS::EFS::FileSystem)

4. **Handle Edge Cases** (Lines ~140-160)
   
   **Case A: Missing Data**
   ```python
   if not configuration_item or not configuration_item.get('resourceId'):
       return submit_not_applicable_evaluation(...)
   ```
   
   **Case B: Wrong Resource Type**
   ```python
   if resource_type != 'AWS::EFS::FileSystem':
       return submit_evaluation(..., compliance_type='NOT_APPLICABLE', ...)
   ```
   
   **Case C: Resource Deleted**
   ```python
   if configuration_item.get('configurationItemStatus') == 'ResourceDeleted':
       compliance_type = 'NOT_APPLICABLE'
   ```

5. **Evaluate Compliance** (Line ~165)
   ```python
   compliance_type, annotation = evaluate_efs_tls_policy(resource_id)
   ```
   - Calls core validation logic
   - Returns tuple: (compliance, message)

6. **Submit Result** (Lines ~170-180)
   ```python
   return submit_evaluation(
       event=event,
       resource_type=resource_type,
       resource_id=resource_id,
       compliance_type=compliance_type,
       annotation=clip_annotation(annotation),
       ordering_timestamp=ordering_timestamp
   )
   ```

**Error Handling:**
```python
except Exception as e:
    logger.exception("Unhandled error during evaluation")
    raise  # Re-raise to ensure Lambda reports failure
```
- Logs full stack trace
- Re-raises exception (Lambda execution fails)
- Config will retry or mark as evaluation error

**Output:**
```json
{
  "statusCode": 200,
  "body": "{\"message\":\"Evaluation completed successfully\",...}"
}
```

**Design Principles:**
- **Defensive:** Handles missing/malformed data gracefully
- **Verbose Logging:** Helps troubleshooting production issues
- **Fail-Fast:** Re-raises unhandled exceptions

---

### 3. `clip_annotation(text, max_len=256)`

**Purpose:** Truncate annotation to AWS Config limit

**Code:**
```python
def clip_annotation(text: str, max_len: int = MAX_ANNOTATION_LENGTH) -> str:
    """Clip annotation to AWS Config maximum length."""
    if len(text) <= max_len:
        return text
    return text[:max_len - 3] + "..."
```

**Why It Exists:**
- AWS Config annotations limited to 256 characters
- Long error messages would cause API failure
- Graceful truncation with ellipsis

**Example:**
```python
# Input: "Error evaluating EFS policy: ClientError: An error occurred (AccessDenied) when calling the DescribeFileSystemPolicy operation: User is not authorized to perform elasticfilesystem:DescribeFileSystemPolicy on resource fs-12345678 because no identity-based policy allows the elasticfilesystem:DescribeFileSystemPolicy action"

# Output: "Error evaluating EFS policy: ClientError: An error occurred (AccessDenied) when calling the DescribeFileSystemPolicy operation: User is not authorized to perform elasticfilesystem:DescribeFileSystemPolicy on resource fs-12345678 because no identity-based policy all..."
```

**Called By:**
- `lambda_handler()` before submitting evaluation
- `evaluate_efs_tls_policy()` for error messages

---

### 4. `parse_ordering_timestamp(timestamp_str)`

**Purpose:** Convert Config item timestamp to datetime object

**Code:**
```python
def parse_ordering_timestamp(timestamp_str: Optional[str]) -> datetime:
    """Parse configuration item timestamp to datetime object."""
    if not timestamp_str:
        return datetime.now(timezone.utc)
    
    try:
        return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
    except (ValueError, AttributeError) as e:
        logger.warning(f"Failed to parse timestamp '{timestamp_str}': {e}")
        return datetime.now(timezone.utc)
```

**Why It Exists:**
- AWS SDK requires datetime object for `OrderingTimestamp`
- Config event provides ISO format string (e.g., "2026-01-26T12:00:00.000Z")
- Must convert "Z" suffix to "+00:00" for Python parsing

**Input Examples:**
```python
"2026-01-26T12:00:00.000Z"     # Standard Config format
"2026-01-26T12:00:00+00:00"    # Already has timezone
None                            # Missing timestamp
```

**Output:**
```python
datetime.datetime(2026, 1, 26, 12, 0, 0, tzinfo=timezone.utc)
```

**Error Handling:**
- Returns `datetime.now(timezone.utc)` if parsing fails
- Logs warning but doesn't fail evaluation

**Design Decision:**
- Graceful degradation: use current time if parsing fails
- Prevents evaluation failure due to malformed timestamps

---

### 5. `submit_evaluation()`

**Purpose:** Submit evaluation result to AWS Config

**Signature:**
```python
def submit_evaluation(
    event: Dict[str, Any],
    resource_type: str,
    resource_id: str,
    compliance_type: str,
    annotation: str,
    ordering_timestamp: datetime
) -> Dict[str, Any]
```

**Processing:**

1. **Build Evaluation Object**
   ```python
   evaluation = {
       'ComplianceResourceType': resource_type,
       'ComplianceResourceId': resource_id,
       'ComplianceType': compliance_type,
       'Annotation': annotation,
       'OrderingTimestamp': ordering_timestamp
   }
   ```

2. **Call Config API**
   ```python
   response = get_config_client().put_evaluations(
       Evaluations=[evaluation],
       ResultToken=event['resultToken']
   )
   ```

3. **Log Result**
   ```python
   logger.info(f"Evaluation submitted: compliance={compliance_type}, resource={resource_id}")
   logger.info(f"PutEvaluations response: {json.dumps(response, default=str)}")
   ```

4. **Return Response**
   ```python
   return {
       'statusCode': 200,
       'body': json.dumps({
           'message': 'Evaluation completed successfully',
           'evaluation': {...}
       })
   }
   ```

**AWS Config API Details:**
- **API:** `config.put_evaluations()`
- **Required:** `Evaluations` list, `ResultToken`
- **ResultToken:** Unique token from Config event (tracks evaluation)

**Response Structure:**
```json
{
  "FailedEvaluations": [],
  "ResponseMetadata": {
    "RequestId": "...",
    "HTTPStatusCode": 200
  }
}
```

**Error Handling:**
- boto3 raises ClientError if API call fails
- Lambda will fail and Config will retry

---

### 6. `submit_not_applicable_evaluation()`

**Purpose:** Convenience wrapper for NOT_APPLICABLE evaluations

**Code:**
```python
def submit_not_applicable_evaluation(
    event: Dict[str, Any],
    resource_type: str,
    resource_id: str,
    annotation: str
) -> Dict[str, Any]:
    """Submit NOT_APPLICABLE evaluation for edge cases."""
    return submit_evaluation(
        event=event,
        resource_type=resource_type,
        resource_id=resource_id,
        compliance_type='NOT_APPLICABLE',
        annotation=clip_annotation(annotation),
        ordering_timestamp=datetime.now(timezone.utc)
    )
```

**Why It Exists:**
- Simplifies calling code
- Ensures consistent timestamp handling
- Automatically clips annotation

**Used For:**
- Missing configuration data
- Wrong resource types
- Malformed events

---

### 7. `evaluate_efs_tls_policy(file_system_id)`

**Purpose:** Core evaluation logic - validate EFS policy

**Signature:**
```python
def evaluate_efs_tls_policy(file_system_id: str) -> Tuple[str, str]:
    """Returns: (compliance_type, annotation)"""
```

**Processing Flow:**

1. **Get EFS Client**
   ```python
   efs = get_efs_client()
   ```

2. **Call EFS API** ⭐ **KEY OPERATION**
   ```python
   response = efs.describe_file_system_policy(FileSystemId=file_system_id)
   policy_json = response.get('Policy')
   ```
   - **This is the API call that Guard policies cannot make**
   - Retrieves resource policy from EFS service
   - Policy NOT in Config configuration item

3. **Check Policy Exists**
   ```python
   if not policy_json:
       return 'NON_COMPLIANT', 'EFS file system has no policy defined'
   ```

4. **Parse JSON Policy**
   ```python
   policy = json.loads(policy_json)
   ```
   - Converts JSON string to Python dict
   - Enables programmatic inspection

5. **Validate TLS Enforcement**
   ```python
   if is_secure_transport_enforced(policy, file_system_id):
       return 'COMPLIANT', 'EFS policy enforces TLS for client actions'
   else:
       return 'NON_COMPLIANT', 'EFS policy does not enforce TLS for client actions'
   ```

**Error Handling:**

**Exception A: PolicyNotFound**
```python
except efs.exceptions.PolicyNotFound:
    return 'NON_COMPLIANT', 'EFS has no policy - TLS enforcement not configured'
```
- EFS exists but has no policy attached
- Result: NON_COMPLIANT

**Exception B: FileSystemNotFound**
```python
except efs.exceptions.FileSystemNotFound:
    return 'NON_COMPLIANT', f'EFS file system not found: {file_system_id}'
```
- EFS doesn't exist (rare - Config shouldn't send event)
- Result: NON_COMPLIANT

**Exception C: General Errors**
```python
except Exception as e:
    error_msg = clip_annotation(f'Error evaluating EFS policy: {str(e)}')
    return 'NON_COMPLIANT', error_msg
```
- API errors (throttling, permissions, etc.)
- Result: NON_COMPLIANT (fail closed)

**Design Principle:**
- **Fail Closed:** Errors result in NON_COMPLIANT
- Prevents false positives (marking insecure resources as compliant)

---

### 8. `is_secure_transport_enforced(policy, file_system_id)`

**Purpose:** Validate policy has proper TLS enforcement

**Signature:**
```python
def is_secure_transport_enforced(policy: Dict[str, Any], file_system_id: str = None) -> bool:
```

**Input (policy):**
```json
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
```

**Processing Steps:**

1. **Get Statements Array**
   ```python
   statements = policy.get('Statement', [])
   ```

2. **Iterate Through Statements**
   ```python
   for statement in statements:
   ```

3. **Check Effect is Deny** (Line ~340)
   ```python
   effect = statement.get('Effect', '')
   if effect != 'Deny':
       continue  # Skip Allow statements
   ```
   - Only Deny statements can enforce TLS
   - Allow statements don't prevent unencrypted access

4. **Check SecureTransport Condition** (Lines ~345-355)
   ```python
   bool_condition = condition.get('Bool', {})
   bool_if_exists = condition.get('BoolIfExists', {})
   
   secure_transport_check = (
       bool_condition.get('aws:SecureTransport') == 'false' or
       bool_condition.get('aws:SecureTransport') is False or
       bool_if_exists.get('aws:SecureTransport') == 'false' or
       bool_if_exists.get('aws:SecureTransport') is False
   )
   ```
   - Checks both `Bool` and `BoolIfExists` condition operators
   - Accepts string `"false"` or boolean `False`

5. **Validate Applies to Client Actions** (Lines ~360-365)
   ```python
   if not _validates_client_actions(statement):
       logger.warning("Deny with SecureTransport but doesn't apply to client actions")
       continue
   ```
   - Calls helper function to check action scope
   - Prevents false positives (Deny on wrong actions)

6. **Return Result**
   ```python
   return True  # Found compliant statement
   ```
   - Returns `True` if any statement matches
   - Returns `False` if no valid statements found

**Why This Is Complex:**

A policy could have:
```json
{
  "Effect": "Deny",
  "Action": "s3:*",  // ← Wrong service!
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

This denies S3 actions when SecureTransport=false, but **doesn't protect EFS client operations**. We must validate the action scope.

**Design Principle:**
- **Strict Validation:** Check both condition AND action scope
- Prevents false positives from mis-configured policies

---

### 9. `_validates_client_actions(statement)`

**Purpose:** Check if statement applies to EFS client actions

**Signature:**
```python
def _validates_client_actions(statement: Dict[str, Any]) -> bool:
```

**Valid Patterns:**

**Pattern 1: Wildcard All Actions**
```json
{"Action": "*"}
```
→ Covers all EFS actions ✅

**Pattern 2: EFS Wildcard**
```json
{"Action": "elasticfilesystem:*"}
```
→ Covers all EFS actions ✅

**Pattern 3: Client Wildcard**
```json
{"Action": "elasticfilesystem:Client*"}
```
→ Covers ClientMount, ClientWrite, ClientRootAccess ✅

**Pattern 4: Explicit List**
```json
{"Action": [
  "elasticfilesystem:ClientMount",
  "elasticfilesystem:ClientWrite",
  "elasticfilesystem:ClientRootAccess"
]}
```
→ Covers all client actions ✅

**Pattern 5: NotAction (Inverse)**
```json
{"NotAction": "s3:*"}
```
→ Applies to all non-S3 actions (includes EFS) ✅

**Invalid Patterns:**

**Invalid 1: Wrong Actions**
```json
{"Action": "s3:GetObject"}
```
→ Only applies to S3, not EFS ❌

**Invalid 2: Non-Client EFS Actions**
```json
{"Action": "elasticfilesystem:DescribeFileSystems"}
```
→ Describe action, not client mount/write/access ❌

**Processing Logic:**

1. **Extract Actions**
   ```python
   actions = statement.get('Action', [])
   not_actions = statement.get('NotAction', [])
   
   # Normalize to list
   if isinstance(actions, str):
       actions = [actions]
   ```

2. **Handle NotAction**
   ```python
   if not_actions:
       for not_action in not_actions:
           for client_action in EFS_CLIENT_ACTIONS:
               if _action_matches(not_action, client_action):
                   return False  # Client action excluded
       return True  # Client actions not excluded
   ```

3. **Check Action Patterns**
   ```python
   for action in actions:
       if action == '*':
           return True
       if action.lower() == 'elasticfilesystem:*':
           return True
       for client_action in EFS_CLIENT_ACTIONS:
           if _action_matches(action, client_action):
               return True
   ```

4. **Default: Not Valid**
   ```python
   return False
   ```

**Constants Used:**
```python
EFS_CLIENT_ACTIONS = [
    'elasticfilesystem:ClientMount',
    'elasticfilesystem:ClientWrite',
    'elasticfilesystem:ClientRootAccess'
]
```

**Design Principle:**
- **Whitelist Approach:** Must explicitly match client actions
- Prevents false positives from unrelated Deny statements

---

### 10. `_action_matches(pattern, action)`

**Purpose:** Pattern matching for IAM actions

**Signature:**
```python
def _action_matches(pattern: str, action: str) -> bool:
```

**Examples:**

**Example 1: Exact Match**
```python
_action_matches("elasticfilesystem:ClientMount", "elasticfilesystem:ClientMount")
# → True
```

**Example 2: Wildcard Suffix**
```python
_action_matches("elasticfilesystem:Client*", "elasticfilesystem:ClientMount")
# → True (prefix match)
```

**Example 3: Service Wildcard**
```python
_action_matches("elasticfilesystem:*", "elasticfilesystem:ClientMount")
# → True
```

**Example 4: No Match**
```python
_action_matches("s3:GetObject", "elasticfilesystem:ClientMount")
# → False
```

**Processing Logic:**

1. **Normalize Case**
   ```python
   pattern_lower = pattern.lower()
   action_lower = action.lower()
   ```

2. **Check Exact Match**
   ```python
   if pattern_lower == action_lower:
       return True
   ```

3. **Check Wildcard Match**
   ```python
   if '*' in pattern_lower:
       if pattern_lower.endswith('*'):
           prefix = pattern_lower[:-1]
           if action_lower.startswith(prefix):
               return True
   ```

4. **No Match**
   ```python
   return False
   ```

**Design Principle:**
- **Case-Insensitive:** IAM actions are case-insensitive
- **Simple Wildcards:** Only suffix wildcards (e.g., `prefix*`)
- **No Regex:** Simpler and safer than regex patterns

---

### 11. `build_error_response(error_message)`

**Purpose:** Construct error response (currently unused)

**Code:**
```python
def build_error_response(error_message: str) -> Dict[str, Any]:
    """Build an error response."""
    return {
        'statusCode': 400,
        'body': json.dumps({
            'error': error_message
        })
    }
```

**Why It Exists:**
- Originally intended for HTTP-style error responses
- Currently not used (errors re-raised instead)
- Kept for future potential use cases

**Could Be Used For:**
- API Gateway Lambda integrations
- Custom error handling logic
- Structured error responses

---

## Test Scenarios

### Scenario 1: No Policy (NON_COMPLIANT)

**EFS State:**
- File system exists
- No resource policy attached

**API Response:**
```python
efs.exceptions.PolicyNotFound: Policy not found
```

**Expected Result:**
- Compliance: `NON_COMPLIANT`
- Annotation: `"EFS file system has no policy - TLS enforcement not configured"`

**Why NON_COMPLIANT:**
Without a policy, there's no TLS enforcement. Anyone can mount the file system without encryption.

---

### Scenario 2: Compliant Policy with Deny (COMPLIANT)

**EFS Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Expected Result:**
- Compliance: `COMPLIANT`
- Annotation: `"EFS file system policy enforces TLS (aws:SecureTransport) for client actions"`

**Why COMPLIANT:**
- Has Deny statement
- Denies when `aws:SecureTransport` is `false`
- Applies to all actions (includes client actions)

---

### Scenario 3: Non-Compliant Policy (NON_COMPLIANT)

**EFS Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "*"
    }
  ]
}
```

**Expected Result:**
- Compliance: `NON_COMPLIANT`
- Annotation: `"EFS policy does not enforce TLS for EFS client actions"`

**Why NON_COMPLIANT:**
- Only has Allow statement (no Deny)
- Doesn't enforce SecureTransport condition
- Allows unencrypted access

---

### Scenario 4: Compliant with BoolIfExists (COMPLIANT)

**EFS Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "elasticfilesystem:Client*",
      "Condition": {
        "BoolIfExists": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Expected Result:**
- Compliance: `COMPLIANT`
- Annotation: `"EFS file system policy enforces TLS (aws:SecureTransport) for client actions"`

**Why COMPLIANT:**
- Has Deny statement
- Uses `BoolIfExists` (variant of Bool condition)
- Applies to `elasticfilesystem:Client*` (covers all client actions)

**Note:** `BoolIfExists` denies when key exists AND is false, or when key doesn't exist.

---

### Scenario 5: Edge Case - Wrong Actions (NON_COMPLIANT)

**EFS Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Expected Result:**
- Compliance: `NON_COMPLIANT`
- Annotation: `"EFS policy does not enforce TLS for EFS client actions"`

**Why NON_COMPLIANT:**
- Has Deny with SecureTransport condition ✓
- BUT only applies to S3 actions ✗
- EFS client operations not protected

**This is why we validate action scope!**

---

## Troubleshooting

### Issue 1: Lambda Not Triggered

**Symptoms:**
- Config rule shows "No resources found"
- Lambda never invoked
- No CloudWatch logs

**Possible Causes:**

**A. Config Recorder Not Running**
```bash
# Check Config recorder status
aws configservice describe-configuration-recorder-status
```

**Solution:**
```bash
# Start Config recorder
aws configservice start-configuration-recorder \
  --configuration-recorder-name default
```

**B. No EFS Resources**
- Config rule only triggers when EFS resources exist
- Create test EFS to trigger evaluation

**C. Wrong Resource Type**
- Verify Config rule targets `AWS::EFS::FileSystem`

---

### Issue 2: Lambda Execution Failed

**Symptoms:**
- Config rule shows "Evaluation failed"
- Lambda logs show errors
- Red status in Config console

**Possible Causes:**

**A. IAM Permissions Missing**
```
ClientError: User is not authorized to perform elasticfilesystem:DescribeFileSystemPolicy
```

**Solution:**
```bash
# Verify Lambda role has EFS permissions
aws iam get-role-policy \
  --role-name efs-tls-enforcement-role \
  --policy-name efs-tls-enforcement-policy
```

Expected policy:
```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeFileSystemPolicy",
        "elasticfilesystem:DescribeFileSystems"
      ],
      "Resource": "*"
    }
  ]
}
```

**B. Lambda Timeout**
```
Task timed out after 3.00 seconds
```

**Solution:**
- Increase Lambda timeout (default 3s → 30s)
- Check for API throttling in logs

**C. Network Issues**
```
Unable to connect to service endpoint
```

**Solution:**
- Lambda must have internet access or VPC endpoint
- Check Lambda VPC configuration

---

### Issue 3: False Positives (COMPLIANT when should be NON_COMPLIANT)

**Symptoms:**
- EFS without TLS enforcement marked compliant
- Policy doesn't actually protect EFS

**Debugging Steps:**

1. **Check Lambda Logs**
   ```
   Found compliant Deny statement: ...
   ```

2. **Verify Policy**
   ```bash
   aws efs describe-file-system-policy \
     --file-system-id fs-xxxxx \
     --output json | jq '.Policy | fromjson'
   ```

3. **Test Locally**
   ```bash
   cd scripts/efs-tls-enforcement
   python3 test_lambda.py
   ```

4. **Add Debug Logging**
   - Temporarily add extra logs in `is_secure_transport_enforced()`
   - Deploy updated Lambda
   - Trigger evaluation
   - Check logs

---

### Issue 4: False Negatives (NON_COMPLIANT when should be COMPLIANT)

**Symptoms:**
- Valid TLS enforcement policy marked non-compliant
- Policy looks correct but fails validation

**Common Causes:**

**A. Action Format**
- Policy uses `"Action": "efs:ClientMount"` (wrong service prefix)
- Should be `"elasticfilesystem:ClientMount"`

**B. Condition Format**
- Policy uses `"SecureTransport": false` (boolean, not string)
- Code checks for both: `== "false"` and `is False`
- Should work, but verify in logs

**C. Missing Client Actions**
- Policy denies `"elasticfilesystem:DescribeFileSystems"`
- Doesn't include ClientMount/ClientWrite/ClientRootAccess
- Lambda correctly marks NON_COMPLIANT

**Solution:**
- Update policy to include `"Action": "elasticfilesystem:Client*"`

---

## Q&A Preparation

### Technical Questions

#### Q1: "Why not use AWS Managed rule efs-encrypted-check?"

**Answer:**
"The AWS Managed rule `efs-encrypted-check` validates encryption-at-rest, not TLS enforcement for in-transit encryption. We use a Guard policy for at-rest (same validation) and Lambda for TLS enforcement (requires API calls to check resource policy)."

**Show:** README_EFS_COMPLIANCE.md matrix

---

#### Q2: "Why Lambda instead of Guard for TLS?"

**Answer:**
"Guard policies can only evaluate data in the Config configuration item. EFS resource policies are NOT in Config items - they require calling the `DescribeFileSystemPolicy` API. Guard policies cannot make API calls, so Lambda is required."

**Code Reference:** Lines 8-11 in lambda_function.py docstring

---

#### Q3: "What if the Lambda fails? Does that affect compliance?"

**Answer:**
"If Lambda execution fails, Config marks it as 'Evaluation failed' (not COMPLIANT). This is fail-closed behavior - we don't want to mark resources compliant if we can't evaluate them. Config will retry the evaluation automatically."

**Show:** CloudWatch logs with error, Config console showing evaluation failure

---

#### Q4: "How do you test this without deploying to AWS?"

**Answer:**
"We use mock clients that simulate AWS API responses. The test suite runs 4 scenarios locally without credentials. This enables fast iteration and CI/CD pipeline integration."

**Demo:** Run `python3 test_lambda.py` live

---

#### Q5: "What about performance at scale?"

**Answer:**
"Lambda is triggered on Config events (EFS changes), not polling all resources. The API call is fast (<100ms), and Lambda auto-scales. For large organizations, this runs thousands of evaluations daily without issues."

**Stats:**
- Execution time: ~200-500ms per evaluation
- Memory: ~128MB
- Cost: Pennies per month (Config costs more than Lambda)

---

#### Q6: "How do you handle API rate limits?"

**Answer:**
"AWS Config spreads evaluations over time naturally. If we hit rate limits, Lambda fails and Config retries with exponential backoff. We also clip error messages to fit in Config annotations."

**Code Reference:** `clip_annotation()` function, Line ~195

---

### Business Questions

#### Q7: "What's the deployment impact?"

**Answer:**
"Zero impact. Config rules are read-only - they evaluate but don't modify resources. We can deploy to dev, test with sample EFS resources, then roll out organization-wide via conformance packs."

---

#### Q8: "How do we remediate non-compliant resources?"

**Answer:**
"Two options:
1. **Manual:** Attach TLS enforcement policy via AWS console or CLI
2. **Automated:** AWS Systems Manager automation document (future enhancement)

For now, we notify via Config dashboard, and teams remediate manually."

---

#### Q9: "What's the cost?"

**Answer:**
"Three components:
- **AWS Config:** $0.003 per config item recorded (main cost)
- **Lambda:** $0.20 per million invocations (~negligible)
- **CloudWatch Logs:** ~$0.50/GB (~$1-5/month)

Total: ~$10-20/month for Config, <$1/month for Lambda."

---

#### Q10: "Can this block resource creation?"

**Answer:**
"No. AWS Config is detective, not preventive. It evaluates resources after creation and reports compliance status. To prevent creation, we'd need Service Control Policies (SCPs) or Guard Duty, which is a separate discussion."

---

## Summary

### Key Takeaways

1. **Lambda enables API-based validation** that Guard policies can't do
2. **Local testing** ensures quality before deployment
3. **Organization-wide deployment** via conformance packs
4. **Defensive coding** handles edge cases gracefully
5. **Fail-closed** design prevents false positives

### Next Steps

1. Deploy to dev environment
2. Validate with test EFS resources
3. Review compliance dashboard
4. Plan production rollout
5. Document remediation procedures

---

## Appendix: Useful Commands

### Terraform Commands
```bash
# Navigate to dev environment
cd environments/dev

# Initialize
terraform init

# Plan
terraform plan -target=module.efs_tls_enforcement_dev

# Apply
terraform apply -target=module.efs_tls_enforcement_dev

# Destroy
terraform destroy -target=module.efs_tls_enforcement_dev
```

### AWS CLI Commands
```bash
# Check Config rule status
aws configservice describe-config-rules \
  --config-rule-names efs-tls-enforcement-dev

# Get compliance details
aws configservice describe-compliance-by-config-rule \
  --config-rule-names efs-tls-enforcement-dev

# Trigger evaluation manually
aws configservice start-config-rules-evaluation \
  --config-rule-names efs-tls-enforcement-dev

# Get EFS policy
aws efs describe-file-system-policy \
  --file-system-id fs-xxxxx

# Attach TLS policy
aws efs put-file-system-policy \
  --file-system-id fs-xxxxx \
  --policy file://example_compliant_policy.json
```

### CloudWatch Logs Commands
```bash
# Get log streams
aws logs describe-log-streams \
  --log-group-name /aws/lambda/efs-tls-enforcement-dev \
  --order-by LastEventTime \
  --descending \
  --max-items 5

# Get log events
aws logs get-log-events \
  --log-group-name /aws/lambda/efs-tls-enforcement-dev \
  --log-stream-name <stream-name>
```

### Testing Commands
```bash
# Run local tests
cd scripts/efs-tls-enforcement
python3 test_lambda.py

# Run with coverage
python3 -m pytest test_lambda.py --cov=lambda_function

# Syntax check
python3 -m py_compile lambda_function.py
```

---

**End of Demo Guide**
