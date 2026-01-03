# Example 1: Audit Mode Deployment (Testing Phase)

This example deploys the AMI governance policies in audit mode for initial testing.

## Configuration

```hcl
module "ami_governance_audit" {
  source = "../terraform-module"
  
  # Target OUs for declarative policy (org-wide)
  org_root_or_ou_ids = [
    "r-abcd",           # Organization root
  ]
  
  # Target OUs for SCP (workload accounts only)
  workload_ou_ids = [
    "ou-abcd-11111111", # Dev OU
    "ou-abcd-22222222", # Test OU
  ]
  
  # Approved AMI publishers
  approved_ami_owner_accounts = [
    "123456738923", # Ops golden AMIs
    "111122223333", # InfoBlox AMI publisher
    "444455556666", # Terraform Enterprise (TFE) AMI publisher
  ]
  
  # Temporary exceptions with expiry dates
  exception_accounts = {
    "777788889999" = "2026-02-28" # AppTeam Sandbox exception
    "222233334444" = "2026-03-15" # M&A migration exception
  }
  
  # Audit mode - logs violations but doesn't block
  policy_mode = "audit_mode"
  
  # Enable both policies
  enable_declarative_policy = true
  enable_scp_policy         = true
  
  tags = {
    Environment = "audit"
    Phase       = "testing"
    Owner       = "platform-team"
  }
}
```

## Deployment Steps

```bash
# Initialize
terraform init

# Plan
terraform plan -out=audit-mode.tfplan

# Apply
terraform apply audit-mode.tfplan

# Monitor CloudTrail and Config for 2-4 weeks
# Review blocked attempts in CloudWatch Logs
```

## What to Monitor

1. **CloudTrail Events**
   - Look for `RunInstances` calls with non-approved AMIs
   - Identify teams/accounts that would be blocked

2. **Config Rules**
   - Check compliance status
   - Review non-compliant resources

3. **Support Tickets**
   - Track requests for exceptions
   - Document use cases

## Outputs

```bash
terraform output approved_ami_owners
terraform output active_exceptions
terraform output policy_summary
```
