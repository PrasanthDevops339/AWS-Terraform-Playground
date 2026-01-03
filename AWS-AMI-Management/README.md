# AWS AMI Governance - Terraform Module

**Feature #1: Declarative Policy for Use of Amazon Machine Images**

This Terraform module implements comprehensive AMI governance controls for AWS Organizations, enforcing that all EC2 launches must use AMIs from approved publishers only.

## 🎯 Overview

### Problem Statement
App teams building/baking their own AMIs creates:
- Security vulnerabilities (unpatched OS, malware)
- Compliance risks (no audit trail)
- Operational complexity (snowflake images)
- Increased attack surface

### Solution
**Golden AMI Strategy** with dual-layer enforcement:
1. **Declarative Policy**: Prevents AMI discovery/use from non-approved publishers
2. **Service Control Policy (SCP)**: Denies instance launches and AMI creation

### Key Benefits
✅ **Security**: Only vetted, hardened AMIs can be used  
✅ **Compliance**: Full audit trail of AMI usage  
✅ **Standardization**: All instances use approved base images  
✅ **Agility**: App teams customize via user-data (immutable infrastructure)  
✅ **Exception Management**: Time-bound exceptions with automatic expiry

---

## 🏗️ Architecture

### Controls Implemented

| Control Type | Purpose | Scope |
|--------------|---------|-------|
| **Declarative Policy** | • Block public AMI sharing<br>• Restrict AMI discovery to approved publishers | Organization-wide |
| **SCP** | • Block instance launches with unapproved AMIs<br>• Prevent AMI creation/import<br>• Prevent AMI sharing modifications | Workload OUs only |

### Approved Publishers

**Permanent (Hard-coded)**:
- `123456738923` - Ops Golden AMI Account
- `111122223333` - InfoBlox AMI Publisher
- `444455556666` - Terraform Enterprise AMI Publisher

**Temporary (Time-bound Exceptions)**:
- `777788889999` - Expires 2026-02-28 (AppTeam Sandbox)
- `222233334444` - Expires 2026-03-15 (M&A Migration)

### Architecture Diagrams
See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed HLD/LLD diagrams.

---

## 📋 Requirements

- Terraform >= 1.0
- AWS Provider >= 5.0
- AWS Organizations enabled
- Organization master/delegated admin access
- Permissions:
  - `organizations:*`
  - `ec2:DescribeImages`
  - `ssm:PutParameter`
  - `sns:Publish`

---

## 🚀 Quick Start

### Step 1: Use the Module

```hcl
module "ami_governance" {
  source = "git::https://github.com/PrasanthDevops339/AWS-Terraform-Playground.git//AWS-AMI-Management/terraform-module?ref=main"
  
  # Target OUs for policies
  org_root_or_ou_ids = [
    "r-abcd",  # Organization root
  ]
  
  # Workload OUs (where SCP will be applied)
  workload_ou_ids = [
    "ou-abcd-11111111",  # Dev OU
    "ou-abcd-22222222",  # Production OU
  ]
  
  # Approved AMI publishers
  approved_ami_owner_accounts = [
    "123456738923",  # Ops golden AMIs
    "111122223333",  # InfoBlox
    "444455556666",  # TFE
  ]
  
  # Temporary exceptions with expiry
  exception_accounts = {
    "777788889999" = "2026-02-28"  # 45-day exception
  }
  
  # Start with audit mode
  policy_mode = "audit_mode"
  
  tags = {
    Environment = "production"
    Owner       = "platform-team"
  }
}

# Optional: Subscribe to expiry notifications
resource "aws_sns_topic_subscription" "ami_exceptions" {
  topic_arn = module.ami_governance.exception_expiry_sns_topic_arn
  protocol  = "email"
  endpoint  = "platform-team@company.com"
}
```

### Step 2: Deploy

```bash
terraform init
terraform plan
terraform apply
```

### Step 3: Monitor

```bash
# Check active exceptions
terraform output active_exceptions

# View policy summary
terraform output policy_summary
```

---

## 📖 Usage

### Audit Mode Deployment

Start with `audit_mode` to test before enforcement:

```hcl
module "ami_governance_audit" {
  source = "./terraform-module"
  
  org_root_or_ou_ids = ["r-abcd"]
  workload_ou_ids    = ["ou-abcd-pilot123"]
  policy_mode        = "audit_mode"  # Logs violations, doesn't block
  
  # ... other config
}
```

**Monitor for 2-4 weeks:**
- Review CloudTrail events
- Check Config compliance
- Identify impacted teams
- Gather feedback

### Production Enforcement

After audit period, enable enforcement:

```hcl
module "ami_governance_production" {
  source = "./terraform-module"
  
  org_root_or_ou_ids = ["r-abcd"]
  workload_ou_ids    = ["ou-abcd-11111111", "ou-abcd-22222222"]
  policy_mode        = "enabled"  # Enforces policies
  
  # ... other config
}
```

### Phased Rollout

```hcl
# Phase 1: Pilot OU
module "phase1_pilot" {
  org_root_or_ou_ids = ["ou-abcd-pilot123"]
  policy_mode        = "enabled"
}

# Phase 2: Dev environments
module "phase2_dev" {
  org_root_or_ou_ids = ["ou-abcd-dev11111"]
  policy_mode        = "enabled"
}

# Phase 3: All workloads
module "phase3_full" {
  org_root_or_ou_ids = ["r-abcd"]
  policy_mode        = "enabled"
}
```

See [examples/](./examples/) for detailed configurations.

---

## 🔧 Configuration

### Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `org_root_or_ou_ids` | list(string) | **required** | OUs to attach declarative policy |
| `workload_ou_ids` | list(string) | `[]` | OUs to attach SCP (if empty, uses org_root_or_ou_ids) |
| `approved_ami_owner_accounts` | list(string) | `[123456738923, ...]` | Permanent approved publishers |
| `exception_accounts` | map(string) | `{...}` | Temporary exceptions (account => expiry date) |
| `policy_mode` | string | `audit_mode` | `audit_mode` or `enabled` |
| `enable_declarative_policy` | bool | `true` | Create declarative policy |
| `enable_scp_policy` | bool | `true` | Create SCP policy |
| `exception_message` | string | (see code) | Custom message shown when launch is blocked |
| `tags` | map(string) | `{}` | Tags for all resources |

### Outputs

| Output | Description |
|--------|-------------|
| `declarative_policy_id` | ID of the declarative policy |
| `scp_policy_id` | ID of the SCP policy |
| `approved_ami_owners` | Combined list of approved accounts (permanent + active exceptions) |
| `active_exceptions` | Map of currently active exceptions |
| `expired_exceptions` | Map of expired exceptions (should be removed) |
| `exception_expiry_sns_topic_arn` | SNS topic for notifications |
| `policy_summary` | Summary statistics |

---

## 🔐 Exception Management

### Requesting an Exception

1. **Submit ServiceNow ticket**: `SNOW-CATALOG-AMI-EXCEPTION`
2. **Provide**:
   - Business justification
   - Account ID
   - Duration (max 90 days)
   - Security review results
3. **Approvals required**:
   - Security Team (2 days SLA)
   - Platform Team (2 days SLA)
   - Chief Architect (if >30 days)

### Implementing an Exception

```bash
# 1. Update variables
vim terraform-module/variables.tf

exception_accounts = {
  # NEW: AppTeam Sandbox Exception
  # Ticket: SNOW-12345
  # Approved: 2026-01-15
  # Expires: 2026-02-28 (45 days)
  # Owner: app-team@company.com
  "777788889999" = "2026-02-28"
}

# 2. Apply
terraform plan
terraform apply

# 3. Verify
terraform output active_exceptions
```

### Automatic Expiry Monitoring

**Daily CI/CD pipeline** checks for:
- Exceptions expiring within 14 days → Warning email
- Exceptions expiring within 7 days → Urgent notification
- Expired exceptions → GitHub issue + SNS alert

**Manual check:**
```bash
cd scripts
python3 exception_manager.py --check --days 14
```

See [runbooks/EXCEPTION-PROCESS.md](./runbooks/EXCEPTION-PROCESS.md) for complete process.

---

## 📚 Examples

### Example 1: Audit Mode
```hcl
module "ami_governance" {
  source             = "./terraform-module"
  org_root_or_ou_ids = ["r-abcd"]
  policy_mode        = "audit_mode"
}
```

### Example 2: Production with Exceptions
```hcl
module "ami_governance" {
  source = "./terraform-module"
  
  org_root_or_ou_ids = ["r-abcd"]
  workload_ou_ids    = ["ou-abcd-11111111", "ou-abcd-22222222"]
  
  exception_accounts = {
    "777788889999" = "2026-02-28"
    "222233334444" = "2026-03-15"
  }
  
  policy_mode = "enabled"
}
```

### Example 3: Custom Exception Message
```hcl
module "ami_governance" {
  source = "./terraform-module"
  
  exception_message = <<-EOT
    ❌ AMI Launch Denied
    
    Contact: platform-team@company.com
    Slack: #ami-governance
  EOT
}
```

See [examples/](./examples/) directory for more.

---

## 🧪 Testing

### Test AMI Launch

```bash
# From workload account - should be denied
aws ec2 run-instances \
  --image-id ami-unauthorized123 \
  --instance-type t3.micro \
  --dry-run

# Expected: UnauthorizedOperation with custom message

# With approved AMI - should succeed
aws ec2 run-instances \
  --image-id ami-approved456 \
  --instance-type t3.micro \
  --dry-run

# Expected: Success (in dry-run mode)
```

### Test AMI Creation

```bash
# From workload account - should be denied
aws ec2 create-image \
  --instance-id i-1234567890abcdef0 \
  --name "my-custom-ami"

# Expected: Access Denied
```

### Test Exception Expiry

```bash
cd scripts
python3 exception_manager.py --check --days 7
```

---

## 📊 Monitoring

### CloudWatch Metrics

Monitor policy effectiveness:
- Policy denials count
- Exception usage patterns
- Compliance rate

### CloudTrail Events

Track blocked actions:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-items 100 \
  | jq '.Events[] | select(.ErrorCode=="UnauthorizedOperation")'
```

### SSM Parameter

Exception tracking data:
```bash
aws ssm get-parameter \
  --name /ami-governance/active-exceptions \
  | jq -r '.Parameter.Value' | jq .
```

---

## 🚨 Troubleshooting

### Issue: Instance launch blocked but account is approved

**Solution**:
1. Check if exception has expired:
   ```bash
   terraform output expired_exceptions
   ```
2. Verify policy propagation (wait 5-10 minutes)
3. Check account ID is correct (12 digits, no spaces)

### Issue: CI/CD pipeline failing on exception check

**Solution**:
```bash
# Run locally to debug
python3 scripts/exception_manager.py --check

# Update expired exceptions
vim terraform-module/variables.tf
terraform apply
```

### Issue: Policy not attaching to OU

**Solution**:
1. Verify OU ID format: `ou-xxxx-xxxxxxxx`
2. Check Organizations is enabled
3. Confirm IAM permissions: `organizations:AttachPolicy`

See [runbooks/EXCEPTION-PROCESS.md](./runbooks/EXCEPTION-PROCESS.md) for more.

---

## 📖 Documentation

- [Architecture Diagrams](./ARCHITECTURE.md)
- [Exception Process Runbook](./runbooks/EXCEPTION-PROCESS.md)
- [Policy Examples](./policies/)
- [Terraform Examples](./examples/)

---

## 🔄 Rollout Plan

### Phase 1: Audit Mode (Weeks 1-2)
- Deploy to pilot OU
- Monitor CloudTrail events
- Identify impacted teams
- Success: <5% false positives

### Phase 2: Pilot Enforcement (Weeks 3-4)
- Enable enforcement in pilot OU
- Provide exception process
- Gather feedback
- Success: No production incidents

### Phase 3: Dev/Test Rollout (Weeks 5-6)
- Expand to dev/test OUs
- Process exceptions
- Success: All teams migrated

### Phase 4: Production Rollout (Weeks 7-10)
- Gradual prod OU rollout
- 24/7 support available
- Success: Full org coverage

---

## 🤝 Contributing

### Adding New Approved Publisher

```hcl
approved_ami_owner_accounts = [
  "123456738923",  # Existing
  "999988887777",  # NEW: Vendor XYZ
]
```

### Extending Exception Duration

Maximum 90 days per exception. For longer periods:
1. Submit new exception request
2. Obtain Chief Architect approval
3. Document business justification

---

## 📄 License

Copyright © 2026 Platform Engineering Team

---

## 📞 Support

- **Email**: platform-team@company.com
- **Slack**: #ami-governance
- **ServiceNow**: SNOW-CATALOG-AMI-EXCEPTION
- **Escalation**: platform-oncall@company.com

---

**Version**: 1.0  
**Last Updated**: 2026-01-03  
**Owner**: Platform Engineering Team  
**Review Cycle**: Quarterly
