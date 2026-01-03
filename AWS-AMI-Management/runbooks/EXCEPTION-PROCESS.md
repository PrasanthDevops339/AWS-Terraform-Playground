# AMI Policy Exception Process Runbook

## Table of Contents
1. [Overview](#overview)
2. [Requesting an Exception](#requesting-an-exception)
3. [Approving an Exception](#approving-an-exception)
4. [Implementing an Exception](#implementing-an-exception)
5. [Monitoring Exceptions](#monitoring-exceptions)
6. [Removing Exceptions](#removing-exceptions)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The AMI Governance Policy enforces that all EC2 instances must use AMIs from approved publishers only. App teams cannot create/bake their own AMIs.

### Approved Publishers (Permanent)
- **Ops Golden AMI Account**: 123456738923
- **InfoBlox**: 111122223333
- **Terraform Enterprise**: 444455556666

### Exception Policy
- Exceptions are **time-bound** (max 90 days)
- Managed via **GitOps** (Terraform variables)
- **Automatic expiry** through CI/CD pipeline
- Require **multi-level approval**

---

## Requesting an Exception

### When to Request
✅ **Valid Reasons:**
- M&A migration requiring legacy AMIs temporarily
- Vendor AMI pending security review/approval
- POC/sandbox requiring specific AMI for evaluation
- Emergency production issue requiring immediate workaround

❌ **Invalid Reasons:**
- Convenience/laziness
- Avoiding golden AMI process
- Long-term custom AMI strategy
- Bypassing security controls

### Request Process

#### Step 1: Submit ServiceNow Ticket

Create ticket in **SNOW-CATALOG-AMI-EXCEPTION**

**Required Fields:**
```yaml
Request Type: AMI Policy Exception
Account ID: [12-digit AWS account]
Account Name: [e.g., "app-team-sandbox"]
Duration: [days, max 90]
Expiry Date: [YYYY-MM-DD]
Business Justification: [detailed explanation]
AMI Details:
  - AMI ID(s): [ami-xxxxx]
  - AMI Owner: [account ID]
  - AMI Purpose: [description]
Technical Contact: [email]
Business Owner: [email]
Security Review Status: [pending/approved]
```

**Attachments:**
- Architecture diagram showing AMI usage
- Security scan results (if available)
- Risk assessment document
- Migration plan (if temporary)

#### Step 2: Provide Justification

Include:
1. **Business Need**: Why is this exception required?
2. **Technical Reason**: Why can't golden AMI be used?
3. **Duration Justification**: Why this specific timeframe?
4. **Mitigation Plan**: How will security risks be managed?
5. **Exit Strategy**: How/when will exception be removed?

**Example Good Justification:**
```
Business Need: 
  Acquisition of ACME Corp requires temporary access to their legacy 
  AMIs during 60-day migration period.

Technical Reason:
  ACME Corp AMIs contain proprietary middleware not yet available in 
  our golden AMI catalog. Replatforming requires additional time.

Duration: 60 days (until 2026-03-15)

Mitigation:
  - AMIs scanned with Qualys (report attached)
  - Network isolated in migration VPC
  - No production traffic
  - Daily monitoring via Security Hub

Exit Strategy:
  Application will be containerized and moved to ECS using golden 
  AMIs by 2026-03-15. Exception auto-expires on that date.
```

---

## Approving an Exception

### Approval Workflow

```
Requester → Security Team → Platform Team → Chief Architect (>30 days)
```

### Security Team Review
**Reviewer**: Application Security Team  
**SLA**: 2 business days

**Checklist:**
- [ ] Business justification is valid
- [ ] AMI security scan completed
- [ ] Risk level is acceptable
- [ ] Compensating controls documented
- [ ] Duration is reasonable
- [ ] Exit strategy is clear

**Decision**: Approve / Reject / Request More Info

### Platform Team Review
**Reviewer**: Platform Engineering Team  
**SLA**: 2 business days

**Checklist:**
- [ ] Technical justification is valid
- [ ] Golden AMI alternatives explored
- [ ] Exception scope is minimal
- [ ] Monitoring plan is adequate
- [ ] Timeline is realistic

**Decision**: Approve / Reject / Request More Info

### Chief Architect Review (30+ days)
**Reviewer**: Chief Architect  
**SLA**: 1 business day

**Checklist:**
- [ ] Strategic alignment
- [ ] Long-term impact assessment
- [ ] Architecture review completed

**Decision**: Approve / Reject

### Approval Outcomes

**✅ Approved:**
- Notification sent to requester
- Ticket assigned to Platform Team for implementation
- SLA: 1 business day for implementation

**❌ Rejected:**
- Detailed rejection reason provided
- Alternative solutions suggested
- Requester may appeal to Chief Architect

**⏸️ More Info Needed:**
- Specific information requested
- Ticket returned to requester
- SLA paused until info provided

---

## Implementing an Exception

### Implementation Process

#### Step 1: Create Git Branch
```bash
cd terraform-ami-governance
git checkout main
git pull origin main
git checkout -b exception/account-777788889999
```

#### Step 2: Update Variables
Edit `terraform-module/variables.tf`:

```hcl
variable "exception_accounts" {
  description = "Map of exception account IDs to expiry dates"
  type        = map(string)
  default = {
    # Existing exceptions...
    
    # NEW: AppTeam Sandbox Exception
    # Ticket: SNOW-12345
    # Approved: 2026-01-15
    # Expires: 2026-02-28 (45 days)
    # Owner: app-team@company.com
    "777788889999" = "2026-02-28"
  }
}
```

**Comment Format (Required):**
```hcl
# NEW/RENEWAL: [Brief description]
# Ticket: [SNOW ticket number]
# Approved: [YYYY-MM-DD]
# Expires: [YYYY-MM-DD] ([N] days)
# Owner: [email]
"[account-id]" = "[expiry-date]"
```

#### Step 3: Validate Configuration
```bash
cd terraform-module
terraform fmt
terraform validate
terraform plan
```

**Review Plan Output:**
- Verify exception account is in approved list
- Check expiry date is correct
- Ensure no other unintended changes

#### Step 4: Create Pull Request

**PR Title:**
```
feat: Add AMI exception for account 777788889999 (SNOW-12345)
```

**PR Description:**
```markdown
## Exception Details
- **Account ID**: 777788889999
- **Account Name**: AppTeam Sandbox
- **Duration**: 45 days
- **Expiry**: 2026-02-28
- **Ticket**: SNOW-12345

## Approvals
- [x] Security Team: @security-reviewer (2026-01-14)
- [x] Platform Team: @platform-lead (2026-01-15)

## Justification
Temporary sandbox exception for POC evaluation.
See ticket SNOW-12345 for full details.

## Auto-Expiry
Exception will automatically be flagged for removal on 2026-02-28
via daily CI/CD check.

## Checklist
- [x] Variables updated with proper comments
- [x] Terraform validate passes
- [x] Terraform plan reviewed
- [x] Expiry date is correct
- [x] ServiceNow ticket linked
```

**Required Reviewers:**
- Platform Team Lead
- At least one SRE

#### Step 5: Merge and Apply

**After PR Approval:**
```bash
# Merge PR
git checkout main
git pull origin main

# Apply Terraform
cd terraform-module
terraform init
terraform plan -out=exception.tfplan
terraform apply exception.tfplan
```

**Verify:**
```bash
# Check outputs
terraform output active_exceptions
terraform output approved_ami_owners

# Test from exception account
aws ec2 run-instances --image-id ami-test --instance-type t3.micro --dry-run
```

#### Step 6: Notify Requester

**Email Template:**
```
Subject: AMI Exception Implemented - Account 777788889999

Hi [Requester],

Your AMI policy exception has been implemented:

Account ID: 777788889999
Expires: 2026-02-28 (45 days)
Ticket: SNOW-12345

You may now launch EC2 instances with AMIs from account [AMI Owner ID].

Important Reminders:
1. Exception expires automatically on 2026-02-28
2. You will receive reminders 14 and 7 days before expiry
3. If renewal is needed, submit new ticket 10 days before expiry
4. After expiry, launches will be blocked again

Questions? Contact platform-team@company.com

Best regards,
Platform Team
```

---

## Monitoring Exceptions

### Daily Automated Checks

**CI/CD Pipeline** (runs daily at 9 AM UTC):
- Checks for expired exceptions
- Checks for exceptions expiring within 14 days
- Creates GitHub issues for action items
- Sends SNS notifications

### Manual Monitoring

#### Check Active Exceptions
```bash
cd terraform-module
terraform output active_exceptions
```

#### Check Expired Exceptions
```bash
terraform output expired_exceptions
```

#### Run Exception Check Script
```bash
cd scripts
python3 exception_manager.py --check --days 14
```

### Notification Schedule

| Days Before Expiry | Action |
|--------------------|--------|
| 14 days | Warning email to requester |
| 7 days | Urgent email to requester + manager |
| 1 day | Critical alert to requester + platform team |
| 0 days (expired) | GitHub issue + SNS alert + Slack notification |
| 3 days after expiry | Escalation to leadership |

---

## Removing Exceptions

### Automatic Removal Process

Exceptions are **not automatically removed from code** to prevent surprise breakage. However, the CI/CD pipeline will:

1. **Detect expired exceptions** daily
2. **Create GitHub issue** with removal instructions
3. **Send notifications** to platform team
4. **Block PR merges** if expired exceptions exist (optional)

### Manual Removal Process

#### Step 1: Verify Expiry
```bash
cd scripts
python3 exception_manager.py --check
```

#### Step 2: Confirm with Requester
Before removing, send final notification:

```
Subject: AMI Exception Expired - Action Required

The AMI exception for account 777788889999 expired on 2026-02-28.

This account will no longer be able to launch instances with 
non-approved AMIs.

If continued access is needed:
1. Submit new exception request via ServiceNow
2. Provide updated justification
3. Allow 5 business days for approval

If no renewal is needed, no action required on your end.
The exception will be removed from the system.
```

#### Step 3: Remove from Code
```bash
git checkout -b remove-exception/account-777788889999

# Edit variables.tf - remove the exception entry
vim terraform-module/variables.tf
```

#### Step 4: Submit Removal PR

**PR Title:**
```
chore: Remove expired AMI exception for account 777788889999
```

**PR Description:**
```markdown
## Removal Details
- **Account ID**: 777788889999  
- **Expired**: 2026-02-28
- **Original Ticket**: SNOW-12345

## Verification
- [x] Exception has expired
- [x] Final notification sent to requester
- [x] No renewal request received
- [x] Terraform plan reviewed

## Impact
Account 777788889999 will no longer be able to launch instances
with non-approved AMIs. This is expected behavior.
```

#### Step 5: Apply Removal
```bash
terraform plan
terraform apply
```

---

## Troubleshooting

### Issue: Exception Not Working

**Symptoms:**
- Instance launch still blocked despite exception

**Diagnosis:**
```bash
# Check if exception is active
cd terraform-module
terraform output active_exceptions | grep "777788889999"

# Check if policy is attached to correct OU
aws organizations list-policies-for-target \
  --target-id ou-abcd-12345 \
  --filter SERVICE_CONTROL_POLICY
```

**Solutions:**
1. Verify exception date hasn't passed
2. Check account ID is correct (12 digits, no spaces)
3. Confirm policy is attached to correct OU
4. Wait 5-10 minutes for policy propagation

### Issue: CI/CD Pipeline Failing

**Symptoms:**
- GitHub Actions workflow fails on exception check

**Diagnosis:**
```bash
# Run locally
python3 scripts/exception_manager.py --check --days 14
```

**Solutions:**
1. Update expired exceptions in variables.tf
2. Fix SSM parameter permissions
3. Check AWS credentials in GitHub Secrets

### Issue: Notifications Not Sending

**Symptoms:**
- No emails/Slack messages for expiring exceptions

**Diagnosis:**
```bash
# Test notification manually
python3 scripts/exception_manager.py \
  --check \
  --days 14 \
  --notify arn:aws:sns:us-east-1:123456789012:ami-exceptions
```

**Solutions:**
1. Verify SNS topic ARN is correct
2. Check SNS topic subscriptions
3. Confirm IAM permissions for SNS publish

### Issue: Terraform Apply Fails

**Symptoms:**
- Error creating/updating policies

**Common Errors:**
```
Error: error creating Organizations Policy: InvalidInputException
```

**Solutions:**
1. Check AWS Organizations is enabled
2. Verify account has organizations:* permissions
3. Ensure policy JSON is valid
4. Confirm target OUs exist

---

## Escalation Path

| Issue Severity | Contact | Response SLA |
|----------------|---------|--------------|
| P1 - Production Down | platform-oncall@company.com | 15 minutes |
| P2 - Service Degraded | platform-team@company.com | 2 hours |
| P3 - Normal Request | ServiceNow | 1 business day |
| P4 - Question | Slack #ami-governance | Best effort |

---

## References

- [AMI Governance Architecture](../ARCHITECTURE.md)
- [Terraform Module README](../terraform-module/README.md)
- [Policy Examples](../policies/)
- [Security Review Process](https://wiki.company.com/security-review)

---

**Last Updated**: 2026-01-03  
**Owner**: Platform Engineering Team  
**Review Cycle**: Quarterly
