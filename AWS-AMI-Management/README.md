# AWS AMI Governance Policies

This folder contains two AWS Organizations policies to enforce AMI governance.

## 📄 Files

1. **declarative-policy-ec2.json** - AWS Organizations Declarative Policy for EC2
2. **scp-ami-guardrail.json** - Service Control Policy (SCP)

## 🚀 How to Use

### Step 1: Apply Declarative Policy

1. Go to [AWS Organizations Console → Policies](https://console.aws.amazon.com/organizations/v2/home/policies)
2. Click **"Declarative policies for EC2"** → **"Create policy"**
3. Name: `ami-governance-declarative-policy`
4. Copy the entire contents of `declarative-policy-ec2.json`
5. Paste into the policy editor
6. Click **"Create policy"**
7. Attach to your **Organization Root**

### Step 2: Apply SCP

1. Go to **"Service control policies"** → **"Create policy"**
2. Name: `scp-ami-guardrail`
3. Copy the entire contents of `scp-ami-guardrail.json`
4. **IMPORTANT:** Replace `o-REPLACE-WITH-YOUR-ORG-ID` with your actual Organization ID
   - Get it: `aws organizations describe-organization --query 'Organization.Id'`
5. Click **"Create policy"**
6. Attach to your **Organization Root**

## ✅ What These Policies Do

### Approved AMI Publishers (allowlist):
- `123456738923` - Ops Golden AMI Publisher
- `111122223333` - InfoBlox
- `444455556666` - Terraform Enterprise
- `777788889999` - Temporary exception (expires 2026-02-28)
- `222233334444` - Temporary exception (expires 2026-03-15)

### Enforced Controls:
1. ✅ Only approved AMI publishers can be used to launch EC2 instances
2. ✅ Blocks public AMI sharing
3. ✅ Prevents AMI creation/copy/import in workload accounts
4. ✅ Dual-layer enforcement (Declarative Policy + SCP)

## 📝 To Update the Allowlist

Edit both JSON files and update the account IDs in:
- `declarative-policy-ec2.json` → `allowed_image_providers` array
- `scp-ami-guardrail.json` → `ec2:Owner` array

**Both arrays must match exactly.**

## ⚙️ Enforcement Mode

Current mode: **`audit_mode`** (logs violations but doesn't block)

To enable enforcement:
- Change `"state": "audit_mode"` to `"state": "enabled"` in `declarative-policy-ec2.json`
- Update the policy in AWS Organizations console

## 📞 Support

For questions or exceptions, contact: cloud-platform-team@company.com
