# Testing Guide - AMI Governance Terraform Module

## 📋 Prerequisites

Before testing, ensure you have:

- [x] AWS CLI configured with Organization admin credentials
- [x] Terraform >= 1.0 installed
- [x] Access to AWS Organizations console
- [x] Organization Root ID ready

## 🧪 Testing Phases

### Phase 0: Pre-Deployment Validation

#### Step 1: Get Your Organization Root ID

```bash
aws organizations describe-organization --query 'Organization.Id' --output text
# Example output: o-abcd1234
```

Save the **Root ID** (starts with `r-`):
```bash
aws organizations list-roots --query 'Roots[0].Id' --output text
# Example output: r-xyz9
```

#### Step 2: Configure Variables

```bash
cd /Users/prasanthkorepally/Documents/GitHub/AWS-Terraform-Playground/AWS-AMI-Management

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vi terraform.tfvars
```

**Minimum Required Configuration:**
```hcl
org_root_id = "r-xyz9"  # Replace with your Root ID

# Start with audit mode for testing
enforcement_mode = "audit_mode"

# Optional: Customize allowlist
ops_publisher_account = "123456738923"

vendor_publisher_accounts = [
  "111122223333",  # InfoBlox
  "444455556666",  # Terraform Enterprise
]

# Optional: Add temporary exceptions
exception_accounts = {
  "777788889999" = "2026-02-28"  # Expires in ~2 months
}
```

#### Step 3: Initialize Terraform

```bash
terraform init
```

**Expected Output:**
```
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v6.27.0...
- Installing hashicorp/null v3.2.4...

Terraform has been successfully initialized!
```

#### Step 4: Validate Configuration

```bash
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

#### Step 5: Format Check

```bash
terraform fmt -check
```

If formatting is needed:
```bash
terraform fmt
```

---

### Phase 1: Audit Mode Testing (RECOMMENDED FIRST)

Deploy policies in **audit mode** to observe behavior without enforcement.

#### Step 1: Plan Deployment

```bash
terraform plan
```

**Review the Plan:**
- [ ] 2 policies will be created (`aws_organizations_policy.declarative_ec2` and `aws_organizations_policy.scp`)
- [ ] 2 policy attachments will be created
- [ ] 1 null_resource for exception validation
- [ ] Check that `approved_ami_owners` output shows correct allowlist

#### Step 2: Apply in Audit Mode

```bash
terraform apply
```

Type `yes` when prompted.

**Expected Output:**
```
aws_organizations_policy.declarative_ec2: Creating...
aws_organizations_policy.scp: Creating...
aws_organizations_policy.declarative_ec2: Creation complete
aws_organizations_policy.scp: Creation complete
aws_organizations_policy_attachment.declarative_ec2: Creating...
aws_organizations_policy_attachment.scp: Creating...

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

approved_ami_owners = [
  "111122223333",
  "123456738923",
  "444455556666",
  "777788889999",
]
declarative_policy_id = "p-abc123"
scp_policy_id = "p-def456"
...
```

#### Step 3: Verify in AWS Console

1. Go to [AWS Organizations Console → Policies](https://console.aws.amazon.com/organizations/v2/home/policies)

2. **Check Declarative Policy:**
   - Navigate to **"Declarative policies for EC2"**
   - Find policy: `ami-governance-declarative-policy`
   - Verify: Attached to Organization Root
   - Check: `"state": "audit_mode"`

3. **Check SCP:**
   - Navigate to **"Service control policies"**
   - Find policy: `scp-ami-guardrail`
   - Verify: Attached to Organization Root

#### Step 4: Test Non-Compliant AMI Launch (Should Succeed in Audit Mode)

In a **workload account** (not in allowlist):

```bash
# Try to launch EC2 instance with non-approved AMI
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --region us-east-1 \
  --dry-run
```

**Expected Result in Audit Mode:**
- ✅ Instance launch succeeds (or dry-run succeeds)
- ⚠️  CloudTrail logs the violation
- ⚠️  No actual blocking occurs

#### Step 5: Monitor CloudTrail Logs

```bash
# Check for policy evaluation events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-results 10 \
  --region us-east-1
```

Look for `declarativePolicy` evaluation in the event details.

#### Step 6: Review Outputs

```bash
# Check approved allowlist
terraform output approved_ami_owners

# Verify no expired exceptions
terraform output expired_exceptions

# View policy summary
terraform output policy_summary
```

**Expected Output:**
```json
{
  "enforcement_mode" = "audit_mode"
  "exception_count" = 1
  "total_approved_accounts" = 4
  "vendor_count" = 2
}
```

#### Step 7: Audit Mode Observation Period

**Recommended Duration:** 2-4 weeks

**Monitor:**
1. CloudTrail for policy evaluation events
2. EC2 launch patterns across accounts
3. Any legitimate workloads using non-approved AMIs

**Action Items:**
- Document any false positives
- Add legitimate publishers to `vendor_publisher_accounts`
- Request exceptions for valid use cases

---

### Phase 2: Enforcement Mode Testing

After successful audit mode observation, switch to enforcement.

#### Step 1: Update Configuration

Edit `terraform.tfvars`:
```hcl
enforcement_mode = "enabled"  # Changed from audit_mode
```

#### Step 2: Plan the Change

```bash
terraform plan
```

**Review:**
- [ ] Only the declarative policy will be **updated** (not replaced)
- [ ] `"state"` changes from `"audit_mode"` to `"enabled"`
- [ ] No other resources should change

#### Step 3: Apply Enforcement

```bash
terraform apply
```

Type `yes` to confirm.

**Expected Output:**
```
aws_organizations_policy.declarative_ec2: Modifying...
aws_organizations_policy.declarative_ec2: Modifications complete

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

#### Step 4: Test Non-Compliant AMI Launch (Should Fail)

In a **workload account** (not in allowlist):

```bash
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --region us-east-1 \
  --dry-run
```

**Expected Result in Enforcement Mode:**
- ❌ Instance launch fails
- ❌ Error message references declarative policy
- ❌ SCP also denies the action

**Example Error:**
```
An error occurred (UnauthorizedOperation) when calling the RunInstances operation:
You are not authorized to perform this operation. The image 'ami-0abcdef1234567890' 
is not from an approved AMI provider. Please use AMIs from approved publishers or 
request an exception at https://jira.company.com/browse/CLOUD
```

#### Step 5: Test Compliant AMI Launch (Should Succeed)

Get an AMI from approved publisher:

```bash
# List AMIs from your ops account
aws ec2 describe-images \
  --owners 123456738923 \
  --region us-east-1 \
  --query 'Images[0].ImageId' \
  --output text

# Launch instance with approved AMI
aws ec2 run-instances \
  --image-id ami-<approved-ami-id> \
  --instance-type t3.micro \
  --region us-east-1 \
  --dry-run
```

**Expected Result:**
- ✅ Dry-run succeeds
- ✅ No policy violations

#### Step 6: Test Exception Account

In an **exception account** (e.g., `777788889999`):

```bash
# Should succeed because account is in exception list
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --region us-east-1 \
  --dry-run
```

**Expected Result:**
- ✅ Succeeds (exception is active)

---

### Phase 3: Exception Management Testing

#### Test 1: Adding a New Exception

1. **Edit `terraform.tfvars`:**
```hcl
exception_accounts = {
  "777788889999" = "2026-02-28"  # Existing
  "123456789012" = "2026-06-30"  # NEW exception
}
```

2. **Apply:**
```bash
terraform apply
```

3. **Verify:**
```bash
terraform output active_exceptions
```

**Expected Output:**
```hcl
{
  "123456789012" = "2026-06-30"
  "777788889999" = "2026-02-28"
}
```

4. **Test:** Launch instance in account `123456789012` with non-approved AMI → Should succeed

#### Test 2: Expired Exception Handling

1. **Simulate expired exception** (edit `terraform.tfvars`):
```hcl
exception_accounts = {
  "777788889999" = "2025-12-31"  # EXPIRED (before today: 2026-01-05)
  "123456789012" = "2026-06-30"  # Active
}
```

2. **Apply:**
```bash
terraform apply
```

**Expected Result:**
- ❌ Apply fails with error from `null_resource.check_expired_exceptions`
- ❌ Error message lists expired accounts

**Example Output:**
```
╷
│ Error: local-exec provisioner error
│ 
│   with null_resource.check_expired_exceptions,
│   on main.tf line X, in resource "null_resource" "check_expired_exceptions":
│
│ ⚠️  WARNING: Found 1 EXPIRED exceptions:
│   • Account: 777788889999 expired on 2025-12-31
│ 
│ Please remove expired exceptions from terraform.tfvars
╵
```

3. **Fix:** Remove expired exception:
```hcl
exception_accounts = {
  # "777788889999" = "2025-12-31"  # REMOVED - expired
  "123456789012" = "2026-06-30"      # Active
}
```

4. **Re-apply:**
```bash
terraform apply
```

**Expected Result:**
- ✅ Apply succeeds
- ✅ Only active exception remains

#### Test 3: Verify Allowlist Updates

```bash
# Before removing exception
terraform output approved_ami_owners
# Output includes: 777788889999

# After removing exception
terraform output approved_ami_owners
# Output excludes: 777788889999
```

---

### Phase 4: Edge Cases & Negative Testing

#### Test 1: Invalid Enforcement Mode

Edit `terraform.tfvars`:
```hcl
enforcement_mode = "blocking"  # INVALID
```

```bash
terraform plan
```

**Expected Result:**
- ❌ Validation error
- ❌ Message: Must be either "audit_mode" or "enabled"

#### Test 2: Invalid Date Format

Edit `terraform.tfvars`:
```hcl
exception_accounts = {
  "123456789012" = "12/31/2026"  # Wrong format
}
```

```bash
terraform apply
```

**Expected Result:**
- ❌ timecmp() function fails
- ❌ Error about invalid date format

#### Test 3: Missing Required Variable

Remove `org_root_id` from `terraform.tfvars`:

```bash
terraform plan
```

**Expected Result:**
- ❌ Error: Missing required variable "org_root_id"

#### Test 4: Duplicate Account IDs

Edit `terraform.tfvars`:
```hcl
vendor_publisher_accounts = [
  "111122223333",
  "111122223333",  # Duplicate
]
```

```bash
terraform apply
```

**Expected Result:**
- ✅ Terraform handles this gracefully (deduplication via toset())
- ✅ Output shows unique accounts only

---

## 🔍 Monitoring & Validation

### Daily Checks

```bash
# Check for expired exceptions
terraform output expired_exceptions

# Should return empty if all exceptions are current
```

### Weekly Review

```bash
# View policy summary
terraform output policy_summary

# View complete allowlist
terraform output approved_ami_owners

# Check Terraform state
terraform state list
```

### Monthly Maintenance

1. **Review exception expiry dates:**
```bash
terraform output active_exceptions
```

2. **Remove or extend exceptions as needed**

3. **Review CloudTrail logs for violation patterns**

---

## 🐛 Troubleshooting

### Issue: "Declarative policy not attached"

**Symptom:** Policy created but not attached to Organization Root

**Fix:**
```bash
# Check policy attachments
terraform state show aws_organizations_policy_attachment.declarative_ec2

# Re-apply if missing
terraform apply -target=aws_organizations_policy_attachment.declarative_ec2
```

### Issue: "SCP conflicts with existing policies"

**Symptom:** Apply fails due to SCP limit or conflict

**Fix:**
```bash
# List existing SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# Check attachment count (max 5 per target)
aws organizations list-policies-for-target --target-id r-xyz9 \
  --filter SERVICE_CONTROL_POLICY
```

### Issue: "Expired exceptions not detected"

**Symptom:** Terraform applies successfully despite expired exceptions

**Fix:** Verify current date in locals:
```bash
terraform console
> local.today
"2026-01-05"
```

### Issue: "Policy not enforcing"

**Symptom:** Non-compliant AMIs still launching in enforcement mode

**Checklist:**
1. Verify enforcement_mode = "enabled" in state:
   ```bash
   terraform show | grep state
   ```

2. Check policy attachment:
   ```bash
   aws organizations list-policies-for-target --target-id r-xyz9 \
     --filter DECLARATIVE_POLICY_EC2
   ```

3. Verify account is not in exception list:
   ```bash
   terraform output active_exceptions
   ```

---

## 📊 Success Criteria

### Phase 1 (Audit Mode) - Complete When:
- [x] Both policies deployed and attached
- [x] CloudTrail shows policy evaluation events
- [x] No blocking occurs for non-compliant AMIs
- [x] Allowlist verified correct
- [x] 2-4 weeks of observation completed

### Phase 2 (Enforcement) - Complete When:
- [x] Non-compliant AMI launches blocked
- [x] Compliant AMI launches succeed
- [x] Exception accounts can use any AMI
- [x] Error messages user-friendly
- [x] No false positives reported

### Phase 3 (Exception Management) - Complete When:
- [x] Can add exceptions dynamically
- [x] Expired exceptions auto-detected and fail apply
- [x] Allowlist updates reflect exception changes
- [x] Manual exception removal works correctly

---

## 🚀 Next Steps After Testing

### 1. Production Rollout
```bash
# Switch to enforcement mode
enforcement_mode = "enabled"

# Apply
terraform apply
```

### 2. Documentation
- Update internal wiki with approved AMI publishers
- Document exception request process
- Create runbook for common scenarios

### 3. Automation
Consider adding:
- Automated exception expiry notifications (SNS/Lambda)
- CloudTrail event alerting for violations
- Dashboard for policy compliance metrics

### 4. Integration
- Link exception request URL to Jira/ServiceNow
- Integrate with CI/CD for AMI publishing workflow
- Add policy compliance checks to AWS Config

---

## 📞 Support

**For issues during testing:**
- Cloud Platform Team: cloud-platform-team@company.com
- Exception Requests: https://jira.company.com/browse/CLOUD
- Emergency: Slack #cloud-platform

**Resources:**
- [AWS Declarative Policies Documentation](https://aws.amazon.com/about-aws/whats-new/2024/12/aws-declarative-policies/)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy)
- [GitHub Issue #40534](https://github.com/hashicorp/terraform-provider-aws/issues/40534)