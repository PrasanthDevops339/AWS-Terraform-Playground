# AMI Governance Runbook

**Owner:** Cloud Platform Team  
**Last Updated:** 2026-01-03  
**Version:** 1.0

---

## Table of Contents

1. [Overview](#overview)
2. [Exception Request Process](#exception-request-process)
3. [Implementing Exceptions](#implementing-exceptions)
4. [Applying Policies at AWS Organizations Root](#applying-policies-at-aws-organizations-root)
5. [Verifying Enforcement](#verifying-enforcement)
6. [Remediating Existing Public AMIs](#remediating-existing-public-amis)
7. [Troubleshooting](#troubleshooting)
8. [Contacts](#contacts)

---

## Overview

### Purpose

This runbook provides operational procedures for managing AMI governance policies across the AWS Organization. The governance framework enforces:

1. **Golden AMI allowlist** - Only approved AMI publisher accounts can be used to launch EC2 instances
2. **No AMI creation/sideload** - Workload accounts cannot create, copy, register, or import AMIs
3. **No public AMI sharing** - Prevents new public AMI sharing across the organization

### Policy Layers

The governance uses **two enforcement layers** for defense-in-depth:

1. **Declarative Policy (EC2)** - Native AWS Organizations policy for EC2 image restrictions
2. **Service Control Policy (SCP)** - Additional enforcement via IAM permission boundaries

Both policies derive from the same source of truth: `config/ami_publishers.json`

### Current Approved Publishers

Run this command to see the current allowlist:

```bash
python scripts/generate_policies.py --mode audit_mode
```

---

## Exception Request Process

### When to Request an Exception

Exceptions are granted **only** for:
- **Migration scenarios** - Transitioning from legacy image pipelines (max 90 days)
- **Vendor POC/pilot** - Testing new vendor products with custom AMIs (max 60 days)
- **Emergency response** - Security patching or incident response (max 30 days)

Exceptions are **NOT granted** for:
- Permanent workload requirements (use ops golden images instead)
- Developer convenience or preference
- Lack of planning or coordination

### Exception Approval Requirements

| Exception Type | Duration | Approvers Required |
|----------------|----------|-------------------|
| Migration | ≤ 90 days | Security Lead + Cloud Architect |
| Vendor POC | ≤ 60 days | Engineering Manager + CTO |
| Emergency | ≤ 30 days | Security Lead + VP Engineering |

### How to Request an Exception

1. **Create a ticket** at your tracking system (e.g., JIRA, ServiceNow)
   - Use template: "AMI Publisher Exception Request"
   
2. **Include required information:**
   ```
   AWS Account ID: 123456789012
   Business Justification: [Detailed explanation]
   Duration Requested: [X days, max 90]
   Workload Description: [What service/application]
   Security Review: [Completed/Pending]
   Migration Plan: [How will you transition off this exception?]
   Technical Contact: [email@company.com]
   Sponsor: [VP/Director name]
   ```

3. **Obtain approvals** from required approvers (see table above)

4. **Submit to Cloud Platform Team** via:
   - Email: cloud-platform-team@company.com
   - Slack: #cloud-platform-requests
   - Ticket: Assign to Cloud-Platform-Team

### SLA

- **Initial Review:** 2 business days
- **Implementation:** 1 business day after approval
- **Total Time:** 3-5 business days

---

## Implementing Exceptions

### Prerequisites

- Approved exception request with ticket number
- Git access to this repository
- Python 3.8+ installed locally

### Step-by-Step Implementation

#### 1. Create a Feature Branch

```bash
git checkout main
git pull origin main
git checkout -b exception/TICKET-NUMBER-account-123456789012
```

#### 2. Edit Configuration File

Open `config/ami_publishers.json` and add the exception to the `exception_accounts` array:

```json
{
  "account_id": "123456789012",
  "expires_on": "2026-04-15",
  "reason": "Migration from legacy image pipeline",
  "ticket": "CLOUD-1234",
  "requested_by": "app-team-alpha",
  "approved_by": "security-lead",
  "approval_date": "2026-01-03",
  "notes": "Team is migrating to ops golden images by April 2026"
}
```

**Important:** Calculate `expires_on` as:
```bash
# Example: 60 days from today
date -d "+60 days" +%Y-%m-%d
```

#### 3. Generate and Validate Policies

```bash
# Generate policies in audit mode
python scripts/generate_policies.py --mode audit_mode

# Validate configuration and policies
python scripts/validate_policies.py
```

Expected output:
```
======================================================================
ACTIVE ALLOWLIST SUMMARY
======================================================================
Total approved accounts: 5
Accounts: 111122223333, 123456738923, 123456789012, 222233334444, 444455556666
======================================================================

✓ Generated: dist/declarative-policy-ec2.json
✓ Generated: dist/scp-ami-guardrail.json
✓ Allowlist consistency verified
✅ VALIDATION PASSED
```

#### 4. Commit and Push

```bash
git add config/ami_publishers.json dist/
git commit -m "feat: Add AMI exception for account 123456789012 (CLOUD-1234)

- Account: 123456789012
- Expires: 2026-04-15
- Reason: Migration from legacy image pipeline
- Approved by: security-lead
- Ticket: CLOUD-1234"

git push origin exception/TICKET-NUMBER-account-123456789012
```

#### 5. Create Merge Request

1. Open GitLab/GitHub
2. Create MR from your feature branch to `main`
3. Add reviewers:
   - Cloud Platform Team member
   - Security team representative (for exceptions)
4. Link the approval ticket in the MR description
5. Wait for CI pipeline to pass

#### 6. Merge and Deploy

After MR approval:

```bash
git checkout main
git pull origin main
```

Proceed to [Applying Policies](#applying-policies-at-aws-organizations-root) section.

#### 7. Monitor Exception Expiry

The CI pipeline runs **daily checks** for expiring exceptions:
- **Warning:** 14 days before expiry
- **Error:** On or after expiry date

**Action Required:**
- Review expiring exceptions 2 weeks before expiry
- Either extend (requires new approval) or remove
- Expired exceptions will **fail the pipeline** until removed

---

## Applying Policies at AWS Organizations Root

### Prerequisites

- [ ] Policies generated in `dist/` directory
- [ ] Validation passed (`python scripts/validate_policies.py`)
- [ ] AWS CLI configured with Organizations admin access
- [ ] Permissions: `organizations:CreatePolicy`, `organizations:AttachPolicy`

### Important Notes

⚠️ **DEPLOYMENT ORDER MATTERS:**
1. Deploy in **audit mode** first
2. Monitor for 2-4 weeks
3. Switch to **enforcement mode** after validation

⚠️ **ROLLBACK PLAN:**
- Keep policy IDs documented
- Can detach policies instantly: `aws organizations detach-policy`
- Can delete policies: `aws organizations delete-policy`

---

### Phase 1: Audit Mode Deployment

#### Step 1: Review Generated Policies

```bash
# View declarative policy
cat dist/declarative-policy-ec2.json | jq '.content.ec2.ec2_attributes.allowed_images_settings.state'
# Expected output: "audit_mode"

# View allowlist
cat dist/declarative-policy-ec2.json | jq '.content.ec2.ec2_attributes.allowed_images_settings.image_criteria.criteria_1.allowed_image_providers'
```

#### Step 2: Create Declarative Policy via Console

1. **Navigate to AWS Organizations Console**
   - URL: https://console.aws.amazon.com/organizations/v2/home/policies

2. **Create Policy**
   - Click: **"Policies" → "Declarative policies for EC2"**
   - Click: **"Create policy"**
   - Policy name: `ami-governance-declarative-policy`
   - Description: `AMI Governance - Restrict EC2 launches to approved AMI publishers (Audit Mode)`

3. **Policy Content**
   - Copy the **entire `content` object** from `dist/declarative-policy-ec2.json`
   - Paste into the policy editor
   - Click: **"Create policy"**

4. **Record Policy ID**
   ```bash
   # Example: p-1234abcd5678
   echo "Declarative Policy ID: p-1234abcd5678" >> deployment-notes.txt
   ```

#### Step 3: Attach Declarative Policy to Root

1. **Navigate to Organization Structure**
   - Click: **"AWS accounts" → "Organization structure"**
   - Select: **Root** (top-level node)

2. **Attach Policy**
   - Click: **"Policies" tab**
   - Click: **"Attach" → "Attach declarative policy for EC2"**
   - Select: `ami-governance-declarative-policy`
   - Click: **"Attach policy"**

3. **Verify Attachment**
   ```bash
   aws organizations list-policies-for-target \
     --target-id r-xxxx \
     --filter DECLARATIVE_POLICY_EC2
   ```

#### Step 4: Create and Attach SCP

1. **Create SCP**
   - Navigate: **"Policies" → "Service control policies"**
   - Click: **"Create policy"**
   - Policy name: `scp-ami-guardrail`
   - Description: `AMI Governance SCP - Deny non-approved AMIs and AMI creation`

2. **Policy Content**
   - Copy the `Statement` array from `dist/scp-ami-guardrail.json`
   - Wrap in a policy document:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       // ... paste Statement array here
     ]
   }
   ```

3. **Update Organization ID Placeholder**
   - Find: `"aws:PrincipalOrgID": "o-placeholder"`
   - Replace with your org ID: `"aws:PrincipalOrgID": "o-abc123xyz"`
   - Get org ID: `aws organizations describe-organization --query 'Organization.Id' --output text`

4. **Attach to Root**
   - Select Root in organization structure
   - Click: **"Policies" → "Attach" → "Attach service control policy"**
   - Select: `scp-ami-guardrail`
   - Click: **"Attach policy"**

5. **Record Policy ID**
   ```bash
   echo "SCP Policy ID: p-5678efgh9012" >> deployment-notes.txt
   ```

#### Step 5: Monitor Audit Mode

**Duration:** 2-4 weeks

**Monitoring Actions:**
1. **Check CloudTrail for violations**
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
     --max-results 50 \
     --query 'Events[?contains(CloudTrailEvent, `not allowed`)]'
   ```

2. **Review AWS Organizations console**
   - Navigate: **"Policies" → "Declarative policies for EC2" → Policy name**
   - Click: **"Compliance status"**
   - Look for violations

3. **Analyze violation patterns**
   - Which accounts are affected?
   - Which AMIs are being blocked?
   - Are these legitimate workloads or violations?

4. **Take Action:**
   - Legitimate workloads: Add exception or migrate to golden AMIs
   - Violations: Work with teams to remediate

---

### Phase 2: Enforcement Mode Deployment

⚠️ **Only proceed after:**
- [ ] Audit mode ran for 2-4 weeks
- [ ] All legitimate violations have exceptions or remediation plans
- [ ] Stakeholders have been notified
- [ ] Change control approval obtained

#### Step 1: Generate Enforcement Mode Policies

```bash
# Generate policies with enforcement enabled
python scripts/generate_policies.py --mode enabled

# Validate
python scripts/validate_policies.py

# Verify enforcement mode
cat dist/declarative-policy-ec2.json | jq '.content.ec2.ec2_attributes.allowed_images_settings.state'
# Expected output: "enabled"
```

#### Step 2: Update Declarative Policy

1. **Navigate to Policy**
   - AWS Organizations Console → Policies → Declarative policies for EC2
   - Click on: `ami-governance-declarative-policy`

2. **Edit Policy**
   - Click: **"Edit policy"**
   - Replace the entire `content` object with the new version from `dist/declarative-policy-ec2.json`
   - **Key change:** `"state": "enabled"` (was `"audit_mode"`)

3. **Save Changes**
   - Click: **"Save changes"**
   - Note: Policy remains attached, enforcement is now active

#### Step 3: Verify Enforcement

Proceed to [Verifying Enforcement](#verifying-enforcement) section.

---

### AWS CLI Alternative (Advanced)

If you prefer CLI-based deployment:

```bash
#!/bin/bash
# deploy-ami-policies.sh

ORG_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)

echo "Organization Root ID: $ORG_ROOT_ID"
echo "Organization ID: $ORG_ID"

# Update SCP with org ID
sed "s/o-placeholder/$ORG_ID/g" dist/scp-ami-guardrail.json > dist/scp-ami-guardrail-final.json

# Create declarative policy
DECL_POLICY_ID=$(aws organizations create-policy \
  --content file://dist/declarative-policy-ec2.json \
  --description "AMI Governance - Restrict EC2 launches to approved AMI publishers" \
  --name "ami-governance-declarative-policy" \
  --type DECLARATIVE_POLICY_EC2 \
  --query 'Policy.PolicySummary.Id' \
  --output text)

echo "Declarative Policy ID: $DECL_POLICY_ID"

# Attach to root
aws organizations attach-policy \
  --policy-id "$DECL_POLICY_ID" \
  --target-id "$ORG_ROOT_ID"

echo "✓ Declarative policy attached to root"

# Create SCP
SCP_POLICY_ID=$(aws organizations create-policy \
  --content file://dist/scp-ami-guardrail-final.json \
  --description "AMI Governance SCP - Deny non-approved AMIs" \
  --name "scp-ami-guardrail" \
  --type SERVICE_CONTROL_POLICY \
  --query 'Policy.PolicySummary.Id' \
  --output text)

echo "SCP Policy ID: $SCP_POLICY_ID"

# Attach to root
aws organizations attach-policy \
  --policy-id "$SCP_POLICY_ID" \
  --target-id "$ORG_ROOT_ID"

echo "✓ SCP attached to root"
echo ""
echo "Deployment complete!"
echo "Save these IDs for rollback:"
echo "  Declarative: $DECL_POLICY_ID"
echo "  SCP: $SCP_POLICY_ID"
```

---

## Verifying Enforcement

### Test Plan

After deploying policies, verify enforcement with controlled tests.

#### Test 1: Launch with Approved AMI (Should Succeed)

```bash
# Use an AMI from your ops publisher account
APPROVED_AMI="ami-abc123def456"  # From account 123456738923

aws ec2 run-instances \
  --image-id "$APPROVED_AMI" \
  --instance-type t3.micro \
  --key-name test-key \
  --subnet-id subnet-xxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ami-governance-test-approved}]' \
  --dry-run

# Expected: DryRunOperation success
# If enforcement mode: launches successfully
# If audit mode: launches successfully but logged as compliant
```

#### Test 2: Launch with Non-Approved AMI (Should Fail)

```bash
# Use an AMI from a non-approved account or AWS marketplace
NON_APPROVED_AMI="ami-xyz789ghi012"  # From random account

aws ec2 run-instances \
  --image-id "$NON_APPROVED_AMI" \
  --instance-type t3.micro \
  --key-name test-key \
  --subnet-id subnet-xxxxx \
  --dry-run

# Expected in enforcement mode:
#   Error: "AMI not approved for use in this organization..."
#   Error code: UnauthorizedException or OperationNotPermitted
#
# Expected in audit mode:
#   DryRunOperation success, but violation logged
```

#### Test 3: Attempt AMI Creation (Should Fail)

```bash
# Try to create an AMI from an existing instance
INSTANCE_ID="i-1234567890abcdef0"

aws ec2 create-image \
  --instance-id "$INSTANCE_ID" \
  --name "test-custom-ami" \
  --no-reboot \
  --dry-run

# Expected: AccessDenied due to SCP
#   "You are not authorized to perform this operation"
```

#### Test 4: Attempt to Make AMI Public (Should Fail)

```bash
# Try to make an AMI public
YOUR_AMI="ami-owned-by-you"

aws ec2 modify-image-attribute \
  --image-id "$YOUR_AMI" \
  --launch-permission "Add=[{Group=all}]" \
  --dry-run

# Expected: AccessDenied due to SCP
#   Blocked by: "DenyPublicAMISharing"
```

### Verification Checklist

- [ ] Approved AMI launches succeed
- [ ] Non-approved AMI launches are blocked (enforcement mode) or logged (audit mode)
- [ ] AMI creation operations are denied
- [ ] AMI copy/import operations are denied
- [ ] Public AMI sharing is denied
- [ ] Exception accounts can launch their own AMIs (until expiry)
- [ ] CloudTrail logs show policy evaluation results

### Monitoring Dashboard

Create a CloudWatch dashboard to track:

1. **EC2 Launch Attempts**
   - Filter: `eventName = RunInstances`
   - Metric: Success vs. denied

2. **AMI Operations**
   - Filter: `eventName IN (CreateImage, CopyImage, RegisterImage, ImportImage)`
   - Metric: Count (should be zero in workload accounts)

3. **Policy Violations**
   - Filter: `errorCode = UnauthorizedException AND eventName = RunInstances`
   - Metric: Count and affected accounts

---

## Remediating Existing Public AMIs

The declarative policy blocks **new** public AMI sharing but does not affect already-public AMIs.

### Step 1: Identify Public AMIs

```bash
#!/bin/bash
# find-public-amis.sh

echo "Scanning for public AMIs across all regions..."

for REGION in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  echo "Checking region: $REGION"
  
  PUBLIC_AMIS=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners self \
    --filters "Name=is-public,Values=true" \
    --query 'Images[].{ID:ImageId,Name:Name,CreationDate:CreationDate}' \
    --output table)
  
  if [ ! -z "$PUBLIC_AMIS" ]; then
    echo "⚠️  PUBLIC AMIs FOUND in $REGION:"
    echo "$PUBLIC_AMIS"
  fi
done
```

### Step 2: Review Public AMIs

For each public AMI found:

1. **Determine if intentional**
   - Is this AMI supposed to be public?
   - Is it shared with partners/customers?
   - Is there a business reason?

2. **Get approval to make private**
   - Security team approval required
   - Notify affected teams/customers

### Step 3: Remove Public Access

```bash
#!/bin/bash
# make-ami-private.sh

AMI_ID="ami-12345678"
REGION="us-east-1"

echo "Making AMI $AMI_ID private in $REGION..."

# Remove public launch permission
aws ec2 modify-image-attribute \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --launch-permission "Remove=[{Group=all}]"

echo "✓ AMI $AMI_ID is now private"

# Verify
aws ec2 describe-image-attribute \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --attribute launchPermission \
  --query 'LaunchPermissions'

# Expected output: [] (empty array) or specific account IDs
```

### Step 4: Document Remediation

Keep a record of remediated AMIs:

```bash
# remediation-log.csv
AMI_ID,Region,Original_Status,Remediation_Date,Remediated_By,Ticket
ami-12345678,us-east-1,public,2026-01-03,ops-team,SEC-9876
ami-23456789,eu-west-1,public,2026-01-03,ops-team,SEC-9876
```

### Step 5: Ongoing Monitoring

Set up a weekly check for public AMIs:

```bash
# Add to crontab or CI schedule
0 9 * * 1 /scripts/find-public-amis.sh | mail -s "Weekly Public AMI Report" security-team@company.com
```

---

## Troubleshooting

### Issue: "Policy validation failed - allowlist mismatch"

**Cause:** Declarative policy and SCP have different allowlists

**Resolution:**
```bash
# Regenerate policies from config
python scripts/generate_policies.py --mode audit_mode

# Validate
python scripts/validate_policies.py

# If still failing, check for manual edits
git diff config/ami_publishers.json
```

---

### Issue: "Exception account still shows as expired in CI"

**Cause:** Exception expired but not removed from config

**Resolution:**
```bash
# Edit config and remove expired exception
vi config/ami_publishers.json

# Or extend expiry if approved
# Update "expires_on" to new date

# Regenerate and commit
python scripts/generate_policies.py
git add config/ami_publishers.json dist/
git commit -m "fix: Remove expired exception ACCOUNT_ID"
```

---

### Issue: "Legitimate workload blocked after enforcement"

**Cause:** Workload using non-approved AMI

**Immediate Resolution (Emergency):**
1. Revert declarative policy to audit mode (see Phase 1, Step 2)
2. Request exception following [exception process](#exception-request-process)

**Long-term Resolution:**
1. Migrate workload to ops golden AMI
2. Customize via user-data instead of custom AMI

---

### Issue: "Cannot apply policy - insufficient permissions"

**Cause:** IAM principal lacks Organizations permissions

**Required Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "organizations:CreatePolicy",
        "organizations:UpdatePolicy",
        "organizations:AttachPolicy",
        "organizations:DetachPolicy",
        "organizations:DescribePolicy",
        "organizations:ListPolicies",
        "organizations:ListPoliciesForTarget"
      ],
      "Resource": "*"
    }
  ]
}
```

---

### Issue: "SCP blocking ops team golden AMI publisher"

**Cause:** Ops publisher account ID incorrect in config

**Resolution:**
```bash
# Verify ops account ID
aws sts get-caller-identity --profile ops-account

# Update config
vi config/ami_publishers.json
# Fix "ops_publisher_account.account_id"

# Regenerate
python scripts/generate_policies.py
```

---

## Contacts

### Escalation Path

| Issue Type | Contact | SLA |
|------------|---------|-----|
| Exception Request | cloud-platform-team@company.com | 2 business days |
| Policy Failure/Outage | Slack: #cloud-platform-oncall | 15 minutes |
| Security Concern | security-team@company.com | 1 hour |
| General Questions | Slack: #cloud-platform-help | 4 hours |

### On-Call Rotation

- **Primary:** Check PagerDuty schedule
- **Secondary:** Check PagerDuty schedule
- **Escalation:** VP Engineering

### Useful Links

- **Policy Dashboard:** https://console.aws.amazon.com/organizations/v2/home/policies
- **CloudTrail Logs:** https://console.aws.amazon.com/cloudtrail/home
- **Exception Tracking:** https://jira.company.com/browse/CLOUD
- **Documentation:** https://gitlab.company.com/cloud/ami-governance

---

## Appendix

### Exception Duration Guidelines

| Scenario | Max Duration | Justification Required |
|----------|--------------|----------------------|
| POC/Pilot | 60 days | Business case, vendor info, exit criteria |
| Migration | 90 days | Migration plan, timeline, resource allocation |
| Emergency | 30 days | Incident details, remediation plan |
| Permanent | 0 days | Not allowed - use golden AMIs instead |

### AMI Naming Conventions

Encourage golden AMI publishers to use consistent naming:

```
{org}-{os}-{version}-{purpose}-{date}
Example: acme-amazon-linux-2023-base-20260103
```

### Related Policies

- Security Policy: SEC-001 - Hardened Operating System Images
- Change Management: CHG-015 - AWS Organizations Policy Changes
- Access Control: IAM-007 - Service Control Policy Management

---

**END OF RUNBOOK**
