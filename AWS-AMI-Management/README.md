# AWS AMI Governance with Terraform

This Terraform module creates and manages AWS Organizations policies to enforce AMI governance using the approach from [hashicorp/terraform-provider-aws#40534](https://github.com/hashicorp/terraform-provider-aws/issues/40534).

## 🎯 Overview

Enforces AMI governance across your AWS Organization:
- ✅ Only approved AMI publishers can be used to launch EC2 instances
- ✅ Blocks public AMI sharing
- ✅ Prevents AMI creation/copy/import in workload accounts
- ✅ Dual-layer enforcement (Declarative Policy + SCP)
- ✅ Time-bound exceptions with automatic expiry checks

## 📁 Files

- `main.tf` - Declarative Policy and SCP resources
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `versions.tf` - Provider requirements
- `terraform.tfvars.example` - Example configuration
- `declarative-policy-ec2.json` - Reference policy JSON
- `scp-ami-guardrail.json` - Reference SCP JSON

## 🚀 Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

Required variable:
```hcl
org_root_id = "r-xxxx"  # Your AWS Organization Root ID
```

### 2. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

### 3. Review Outputs

```bash
terraform output policy_summary
terraform output approved_ami_owners
terraform output active_exceptions
```

## 📖 Usage Examples

### Basic Configuration

```hcl
# terraform.tfvars
org_root_id = "r-abcd1234"

enforcement_mode = "audit_mode"  # Start with audit mode
```

### Custom AMI Publishers

```hcl
ops_publisher_account = "123456738923"

vendor_publisher_accounts = [
  "111122223333",  # InfoBlox
  "444455556666",  # Terraform Enterprise
  "999888777666"   # Custom vendor
]
```

### Adding Exceptions

```hcl
exception_accounts = {
  "777788889999" = "2026-02-28"  # Migration exception
  "222233334444" = "2026-03-15"  # ML POC exception
  "555544443333" = "2026-01-31"  # Emergency exception
}
```

## ⚙️ Configuration

### Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `org_root_id` | string | **required** | AWS Organization Root ID |
| `ops_publisher_account` | string | `123456738923` | Ops golden AMI publisher |
| `vendor_publisher_accounts` | list(string) | `[...]` | Vendor AMI publishers |
| `exception_accounts` | map(string) | `{...}` | Exception accounts with expiry dates |
| `enforcement_mode` | string | `audit_mode` | `audit_mode` or `enabled` |
| `exception_request_url` | string | `https://jira.company.com` | Exception request URL |
| `tags` | map(string) | `{...}` | Tags for all resources |

### Outputs

| Output | Description |
|--------|-------------|
| `declarative_policy_id` | Declarative policy ID |
| `scp_policy_id` | SCP policy ID |
| `approved_ami_owners` | Complete allowlist |
| `active_exceptions` | Currently active exceptions |
| `expired_exceptions` | Expired exceptions (should be removed) |
| `policy_summary` | Summary statistics |

## 🔄 Workflow

### Phase 1: Audit Mode (Recommended First)

```hcl
enforcement_mode = "audit_mode"
```

Deploy and monitor for 2-4 weeks:
```bash
terraform apply
```

Check CloudTrail for violations but instances still launch.

### Phase 2: Enforcement Mode

```hcl
enforcement_mode = "enabled"
```

Apply changes:
```bash
terraform apply
```

Now non-approved AMIs are blocked.

## 🛡️ Exception Management

### Adding an Exception

1. Update `terraform.tfvars`:
```hcl
exception_accounts = {
  "777788889999" = "2026-02-28"
  "123456789012" = "2026-04-30"  # New exception
}
```

2. Apply:
```bash
terraform apply
```

3. Review:
```bash
terraform output active_exceptions
```

### Automatic Expiry Checks

Terraform will **fail** if you have expired exceptions:

```bash
terraform apply
# ⚠️  WARNING: Found 1 EXPIRED exceptions:
#   • Account: 777788889999 expired on 2025-12-31
# Please remove expired exceptions from variables.tf
```

Remove expired exceptions and re-run.

## 📊 Monitoring

### Check Policy Status

```bash
# View all approved accounts
terraform output approved_ami_owners

# Check for expired exceptions
terraform output expired_exceptions

# View policy summary
terraform output policy_summary
```

### AWS Console

View policies in [AWS Organizations Console](https://console.aws.amazon.com/organizations/v2/home/policies)

## 🔐 Policy Details

### Approved AMI Publishers (Default Allowlist)

- `123456738923` - Ops Golden AMI Publisher
- `111122223333` - InfoBlox
- `444455556666` - Terraform Enterprise
- Plus any active (non-expired) exception accounts

### Enforcement Layers

1. **Declarative Policy** (`DECLARATIVE_POLICY_EC2`)
   - Native AWS Organizations control
   - Blocks AMI discovery from non-approved publishers
   - User-friendly exception messages

2. **Service Control Policy** (SCP)
   - IAM permission boundary
   - Blocks EC2 launches with unapproved AMIs
   - Blocks AMI creation/copy/import
   - Blocks public AMI sharing

## 🔧 Maintenance

### Updating the Allowlist

Edit `terraform.tfvars` and run `terraform apply`.

### Switching Enforcement Mode

```bash
# Edit terraform.tfvars
enforcement_mode = "enabled"

# Apply
terraform apply
```

### Removing Expired Exceptions

```bash
# Edit terraform.tfvars - remove expired entries
exception_accounts = {
  # "777788889999" = "2025-12-31"  # REMOVED - expired
  "222233334444" = "2026-03-15"     # Still active
}

# Apply
terraform apply
```

## 📞 Support

For questions or exceptions, contact: cloud-platform-team@company.com

## 🔗 References

- [AWS Declarative Policies Announcement](https://aws.amazon.com/about-aws/whats-new/2024/12/aws-declarative-policies/)
- [Terraform Provider Issue #40534](https://github.com/hashicorp/terraform-provider-aws/issues/40534)
- [AWS Organizations API Documentation](https://docs.aws.amazon.com/organizations/latest/APIReference/)
