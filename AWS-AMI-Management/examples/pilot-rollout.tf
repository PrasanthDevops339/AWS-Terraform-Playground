# Example 3: Pilot OU Deployment

This example shows a phased rollout starting with a single pilot OU.

## Phase 1: Single Pilot OU

```hcl
module "ami_governance_pilot" {
  source = "../terraform-module"
  
  # Start with a single pilot OU
  org_root_or_ou_ids = [
    "ou-abcd-pilot123", # Non-production pilot OU
  ]
  
  workload_ou_ids = [
    "ou-abcd-pilot123",
  ]
  
  approved_ami_owner_accounts = [
    "123456738923", # Ops golden AMIs
    "111122223333", # InfoBlox
    "444455556666", # TFE
  ]
  
  exception_accounts = {
    "888899990000" = "2026-01-31" # Pilot team exception for testing
  }
  
  policy_mode = "enabled"
  
  enable_declarative_policy = true
  enable_scp_policy         = true
  
  tags = {
    Phase = "pilot"
    OU    = "pilot-ou"
  }
}
```

## Phase 2: Expand to Dev Environment

```hcl
module "ami_governance_dev" {
  source = "../terraform-module"
  
  org_root_or_ou_ids = [
    "ou-abcd-dev11111",
  ]
  
  workload_ou_ids = [
    "ou-abcd-dev11111",
  ]
  
  approved_ami_owner_accounts = [
    "123456738923",
    "111122223333",
    "444455556666",
  ]
  
  exception_accounts = {}
  
  policy_mode = "enabled"
  
  enable_declarative_policy = true
  enable_scp_policy         = true
  
  tags = {
    Phase = "dev-rollout"
  }
}
```

## Phase 3: Full Organization Rollout

```hcl
module "ami_governance_full" {
  source = "../terraform-module"
  
  # Apply to organization root
  org_root_or_ou_ids = [
    "r-abcd",
  ]
  
  # All workload OUs (exclude security/ops)
  workload_ou_ids = [
    "ou-abcd-dev11111",
    "ou-abcd-test2222",
    "ou-abcd-stg33333",
    "ou-abcd-prod4444",
  ]
  
  approved_ami_owner_accounts = [
    "123456738923",
    "111122223333",
    "444455556666",
  ]
  
  exception_accounts = {
    "777788889999" = "2026-02-28"
    "222233334444" = "2026-03-15"
  }
  
  policy_mode = "enabled"
  
  enable_declarative_policy = true
  enable_scp_policy         = true
  
  tags = {
    Phase = "full-rollout"
  }
}
```

## Rollout Timeline

| Phase | Duration | OUs | Mode | Success Criteria |
|-------|----------|-----|------|------------------|
| 1. Pilot | 2 weeks | 1 pilot OU | enabled | <5% false positives, team satisfaction >80% |
| 2. Dev | 2 weeks | Dev OUs | enabled | No production impact, processes documented |
| 3. Test/Staging | 2 weeks | Test + Staging | enabled | All teams migrated to golden AMIs |
| 4. Production | 4 weeks | All prod OUs | enabled | Zero unplanned exceptions, SLA met |

## Monitoring During Rollout

```bash
# Check policy effectiveness
aws organizations describe-effective-policy \
  --policy-type DECLARATIVE_POLICY_EC2 \
  --target-id ou-abcd-pilot123

# Review denied actions in CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-items 100 \
  | jq '.Events[] | select(.ErrorCode=="UnauthorizedOperation")'
```
