# AWS Console Testing Guide - Declarative Policy

**File**: `declarative-policy-ec2-console-test.json`
**Purpose**: Fully hardcoded version for direct AWS Console testing
**Created**: 2026-02-11

## Quick Start

### 1. Open AWS Organizations Console

Navigate to: https://console.aws.amazon.com/organizations/v2/home/policies

### 2. Create New Policy

1. Click **"Policies"** in the left navigation
2. Select **"Declarative policies"** tab
3. Click **"Create policy"**
4. Select **"EC2"** as the service

### 3. Copy-Paste Policy Content

Copy the entire contents of `declarative-policy-ec2-console-test.json` and paste it into the policy editor.

### 4. Configure Policy Settings

**Policy Name**: `ami-governance-test-policy`
**Description**: `Test policy for AMI governance - audit mode only`
**Policy Type**: `DECLARATIVE_POLICY_EC2`

### 5. Attach to Test OU/Account

Attach the policy to a test OU or account to validate behavior.

---

## Current Configuration

### Enforcement Mode
✅ **`audit_mode`** - Logs violations without blocking (safe for testing)

To switch to enforcement mode, change line 11:
```json
"state": {
  "@@assign": "enabled"
}
```

### Approved AMI Sources

#### Criteria 1: Prasa Operations AMIs
- **Accounts**: 565656565656, 666363636363
- **Pattern**: Any (no restriction)
- **Age**: < 300 days
- **Deprecated**: No

#### Criteria 2: Golden AMIs
- **Account**: 123456789014
- **Pattern**: `golden-ami-*` only
- **Age**: < 300 days
- **Deprecated**: No

---

## Testing Steps

### Phase 1: Policy Creation (5 min)
1. ✅ Create policy in AWS Organizations console
2. ✅ Validate JSON syntax is accepted
3. ✅ Verify policy is created successfully

### Phase 2: Policy Attachment (5 min)
1. ✅ Attach to test OU or account
2. ✅ Check effective policy on target account:
   ```bash
   aws organizations describe-effective-policy \
     --policy-type DECLARATIVE_POLICY_EC2 \
     --target-id <account-id>
   ```

### Phase 3: Audit Mode Testing (30 min)
1. ✅ Launch instance with **approved** AMI (from 565656565656)
   - Should succeed
   - Check CloudTrail for `imageAllowed=true`

2. ✅ Launch instance with **non-approved** AMI (public AWS AMI)
   - Should succeed (audit mode doesn't block)
   - Check CloudTrail for `imageAllowed=false`

3. ✅ Launch instance with **golden AMI** (from 123456789014)
   - Should succeed
   - Check CloudTrail for `imageAllowed=true`

### Phase 4: Enforcement Mode Testing (OPTIONAL)
⚠️ **WARNING**: Only test in non-production environment!

1. Update policy state to `"enabled"`
2. Try launching non-approved AMI
   - Should be **BLOCKED**
   - Verify error message matches `exception_message`

---

## CloudTrail Monitoring

### Find Audit Mode Events
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-results 50 | jq '.Events[] | select(.CloudTrailEvent | contains("imageAllowed"))'
```

### Check for Blocked Launches (Enforcement Mode)
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-results 50 | jq '.Events[] | select(.CloudTrailEvent | contains("AccessDenied"))'
```

---

## Expected Results

### Approved AMI Launch (Should Succeed)

**AMI Owner**: 565656565656
**AMI Name**: prasa-rhel8-2024-01-15
**Result**: ✅ Launch succeeds
**CloudTrail**: `imageAllowed: true`

### Non-Approved AMI Launch (Audit Mode)

**AMI Owner**: amazon (137112412989)
**AMI Name**: amzn2-ami-kernel-5.10
**Result**:
- Audit Mode: ✅ Launch succeeds, but logged
- Enforcement Mode: ❌ Launch blocked

**CloudTrail**: `imageAllowed: false`

### Golden AMI Launch (Should Succeed)

**AMI Owner**: 123456789014
**AMI Name**: golden-ami-ubuntu-2024
**Result**: ✅ Launch succeeds
**CloudTrail**: `imageAllowed: true`

### Old AMI Launch (> 300 days)

**AMI Owner**: 565656565656
**AMI Age**: 350 days
**Result**:
- Audit Mode: ✅ Launch succeeds, but logged
- Enforcement Mode: ❌ Launch blocked

**Reason**: Exceeds maximum age (300 days)

### Deprecated AMI Launch

**AMI Owner**: 565656565656
**Deprecated**: Yes
**Result**:
- Audit Mode: ✅ Launch succeeds, but logged
- Enforcement Mode: ❌ Launch blocked

**Reason**: AMI is deprecated

---

## Switching Between Modes

### Audit Mode (Current)
```json
"state": {
  "@@assign": "audit_mode"
}
```
- Logs violations
- Does NOT block launches
- Safe for testing

### Enforcement Mode
```json
"state": {
  "@@assign": "enabled"
}
```
- Logs violations
- **BLOCKS** non-compliant launches
- Use only after audit validation

### Disabled Mode
```json
"state": {
  "@@assign": "disabled"
}
```
- Policy inactive
- No logging, no blocking

---

## Troubleshooting

### Policy Creation Fails
❌ **Error**: "Invalid policy document"
✅ **Fix**: Verify JSON syntax with `jq`:
```bash
cat declarative-policy-ec2-console-test.json | jq .
```

### Policy Has No Effect
❌ **Issue**: Launches not being evaluated
✅ **Check**:
1. Verify policy is attached to correct OU/account
2. Check effective policy on target account
3. Ensure policy state is not "disabled"

### CloudTrail Shows No Events
❌ **Issue**: Can't see imageAllowed indicators
✅ **Check**:
1. CloudTrail is enabled
2. Looking in correct region
3. Using correct event name (RunInstances)

---

## Clean Up

### Remove Policy Attachment
```bash
aws organizations detach-policy \
  --policy-id <policy-id> \
  --target-id <ou-or-account-id>
```

### Delete Policy
```bash
aws organizations delete-policy \
  --policy-id <policy-id>
```

---

## Files Reference

| File                                        | Purpose                              |
|---------------------------------------------|--------------------------------------|
| `declarative-policy-ec2-console-test.json` | Hardcoded policy for console testing |
| `declarative-policy-ec2-2026-01-18.json`   | Terraform template with variables    |
| `scp-ami-guardrail-2026-01-18.json`        | Hardcoded SCP policy                 |

---

## Additional Resources

- **AWS Documentation**: [EC2 Declarative Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html)
- **AMI Governance Overview**: See `AMI-GOVERNANCE-OVERVIEW.md`
- **Change History**: See `FIXES-APPLIED.md`

---

**Last Updated**: 2026-02-11
**Status**: ✅ Ready for Console Testing
