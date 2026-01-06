# AWS AMI Governance with Terraform

Enterprise-grade AMI governance solution for AWS Organizations using Terraform. Enforces approved AMI usage across your organization with dual-layer protection (Declarative Policy + SCP).

## 📁 Repository Structure

```
AWS-AMI-Management/
├── .gitlab-ci.yml                  # GitLab CI/CD pipeline
├── README.md                       # This file
├── TESTING.md                      # Comprehensive testing guide
├── modules/                        # Reusable Terraform modules
│   └── ami-governance/             # AMI governance module
│       ├── main.tf                 # Policy resources and logic
│       ├── variables.tf            # Module input variables
│       └── outputs.tf              # Module outputs
├── environments/                   # Environment-specific configurations
│   └── prd/                        # Production environment
│       ├── main.tf                 # Module invocation
│       ├── variables.tf            # Environment variables
│       ├── outputs.tf              # Environment outputs
│       └── prd.auto.tfvars         # Production configuration (auto-loaded)
└── policies/                       # Reference JSON policy files
    ├── declarative-policy-ec2-2026-01-06.json
    └── scp-ami-guardrail-2026-01-06.json
```

## 🎯 Overview

This solution enforces AMI governance across your AWS Organization with:

- ✅ **Dual-Layer Enforcement**: Declarative Policy (native AWS) + SCP (IAM boundary)
- ✅ **Approved Publishers Only**: Only specified AWS accounts can publish AMIs
- ✅ **Time-Bound Exceptions**: Automatic expiry checking for temporary exceptions
- ✅ **Audit Mode Support**: Test before enforcing with audit_mode
- ✅ **Modular Design**: Reusable module for multi-environment deployment
- ✅ **CI/CD Ready**: GitLab pipeline with validation, plan, and apply stages

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with Organization admin credentials
- Terraform >= 1.0
- AWS Provider >= 5.0 (for DECLARATIVE_POLICY_EC2 support)
- GitLab Runner (for CI/CD) or local Terraform execution

### 1. Configure Production Environment

```bash
cd environments/prd
vi prd.auto.tfvars
```

**Required Configuration:**

```hcl
# Update with your Organization Root ID or OU IDs
target_ids = ["r-xxxx"]  # Your Organization Root ID

# Customize AMI publisher allowlist
ops_publisher_account = "123456738923"

vendor_publisher_accounts = [
  "111122223333",  # InfoBlox
  "444455556666",  # Terraform Enterprise
]

# Add temporary exceptions (if needed)
exception_accounts = {
  "777788889999" = "2026-02-28"  # Migration exception
}

# Start with audit mode (recommended)
enforcement_mode = "audit_mode"
```

### 2. Initialize and Deploy

```bash
cd environments/prd

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Review execution plan
terraform plan

# Apply (start with audit mode)
terraform apply
```

### 3. Monitor and Switch to Enforcement

After 2-4 weeks of monitoring CloudTrail logs:

```hcl
# Update prd.auto.tfvars
enforcement_mode = "enabled"
```

```bash
terraform apply
```

## 📖 Module Usage

### Basic Module Invocation

```hcl
module "ami_governance" {
  source = "../../modules/ami-governance"

  # Environment configuration
  environment = "prd"

  # Policy targets
  target_ids = ["r-xxxx"]  # Root/OU/Account IDs

  # AMI Publisher Allowlist
  ops_publisher_account     = "123456738923"
  vendor_publisher_accounts = ["111122223333", "444455556666"]

  # Exception Management
  exception_accounts = {
    "777788889999" = "2026-02-28"
  }

  # Enforcement
  enforcement_mode = "audit_mode"  # or "enabled"

  # Tags
  tags = {
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}
```

### Module Outputs

```hcl
output "approved_ami_owners" {
  value = module.ami_governance.approved_ami_owners
}

output "policy_summary" {
  value = module.ami_governance.policy_summary
}
```

## ⚙️ Configuration

### Environment Variables

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `environment` | string | Yes | Environment name (dev/prd) |
| `target_ids` | list(string) | Yes | Root/OU/Account IDs for policy attachment |
| `ops_publisher_account` | string | Yes | Ops golden AMI publisher account ID |
| `vendor_publisher_accounts` | list(string) | No | Approved vendor account IDs |
| `exception_accounts` | map(string) | No | Exception accounts with expiry dates |
| `enforcement_mode` | string | No | `audit_mode` or `enabled` (default: audit_mode) |
| `exception_request_url` | string | No | URL for exception requests |
| `tags` | map(string) | No | Resource tags |

### Enforcement Modes

#### Audit Mode (Recommended First)
```hcl
enforcement_mode = "audit_mode"
```
- Logs violations in CloudTrail
- Does NOT block EC2 launches
- Allows monitoring before enforcement

#### Enforcement Mode
```hcl
enforcement_mode = "enabled"
```
- Actively blocks non-compliant AMI launches
- Shows user-friendly error messages
- Exception accounts still work

## 🔄 CI/CD Pipeline

### GitLab Pipeline Stages

1. **Validate** (automatic)
   - Terraform validation
   - Format checking
   - Runs on all branches and MRs

2. **Plan** (automatic)
   - Generates Terraform plan
   - Saves plan artifacts
   - Available for review

3. **Apply** (manual approval required)
   - Applies changes to production
   - Only on main branch
   - Requires manual trigger

### Running Locally

```bash
# Validate
cd environments/prd
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

## 🛡️ Exception Management

### Adding an Exception

Edit `prd.auto.tfvars`:

```hcl
exception_accounts = {
  "777788889999" = "2026-02-28"   # Existing
  "123456789012" = "2026-04-30"   # NEW exception
}
```

```bash
terraform apply
```

### Automatic Expiry Checks

The module automatically:
- Filters active exceptions (not expired)
- Detects expired exceptions
- **FAILS** `terraform apply` if expired exceptions exist

**Example Error:**
```
⚠️  WARNING: Found 1 EXPIRED exceptions:
  • Account: 777788889999 expired on 2025-12-31

Please remove expired exceptions from terraform.tfvars
```

**Fix:** Remove expired entries and re-apply.

### Removing an Exception

```hcl
exception_accounts = {
  # "777788889999" = "2026-02-28"  # REMOVED
  "123456789012" = "2026-04-30"    # Still active
}
```

## 📊 Monitoring

### Check Outputs

```bash
# View approved AMI owners
terraform output approved_ami_owners

# Check for expired exceptions
terraform output expired_exceptions

# View policy summary
terraform output policy_summary
```

### CloudTrail Monitoring

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-results 10
```

Look for `declarativePolicy` evaluation events.

## 📂 Policy Files

Reference JSON policy files are stored in `policies/` directory:

- `declarative-policy-ec2-YYYY-MM-DD.json` - Declarative Policy template
- `scp-ami-guardrail-YYYY-MM-DD.json` - SCP template

These files are for reference only. The module generates policies dynamically.

## 🔧 Troubleshooting

### Issue: "Declarative policy not attached"

```bash
# Check policy attachments
terraform state show module.ami_governance.aws_organizations_policy_attachment.declarative_ec2[\"r-xxxx\"]

# Re-apply
terraform apply
```

### Issue: "Expired exceptions not detected"

```bash
# Check today's date calculation
terraform console
> local.today
"2026-01-06"
```

### Issue: "Module not found"

Ensure you're in the correct directory:
```bash
cd environments/prd
terraform init
```

## 📚 Additional Documentation

- [TESTING.md](TESTING.md) - Comprehensive testing guide with phase-by-phase instructions
- [AWS Declarative Policies Documentation](https://aws.amazon.com/about-aws/whats-new/2024/12/aws-declarative-policies/)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy)
- [GitHub Issue #40534](https://github.com/hashicorp/terraform-provider-aws/issues/40534) - DECLARATIVE_POLICY_EC2 support

## 🔗 References

This repository follows the structure and patterns from the enterprise [aws-service-control-policies](../aws-service-control-policies) repository:

- Modular design with reusable modules
- Environment-based configuration (dev/prd)
- Auto-loading variable files (*.auto.tfvars)
- Reference JSON policy storage
- GitLab CI/CD pipeline

## 📞 Support

**For questions or exceptions:**
- Cloud Platform Team: cloud-platform-team@company.com
- Exception Requests: https://jira.company.com/browse/CLOUD
- Emergency: Slack #cloud-platform

## 📝 License

Internal use only - Company Proprietary

---

**Version:** 2.0.0 (Modular Architecture)  
**Last Updated:** January 6, 2026  
**Maintained By:** Cloud Platform Team
