# Example 2: Production Enforcement Mode

This example deploys the AMI governance policies with full enforcement.

## Configuration

```hcl
module "ami_governance_production" {
  source = "../terraform-module"
  
  # Target OUs for declarative policy (org-wide)
  org_root_or_ou_ids = [
    "r-abcd",           # Organization root
  ]
  
  # Target OUs for SCP (exclude security/ops OUs)
  workload_ou_ids = [
    "ou-abcd-11111111", # Dev OU
    "ou-abcd-22222222", # Test OU
    "ou-abcd-33333333", # Staging OU
    "ou-abcd-44444444", # Production OU
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
  
  # Production mode - enforces policies
  policy_mode = "enabled"
  
  # Enable both policies
  enable_declarative_policy = true
  enable_scp_policy         = true
  
  # Custom exception message
  exception_message = <<-EOT
    ❌ AMI Launch Denied
    
    This EC2 instance launch was blocked because the AMI is not from an approved publisher.
    
    📋 Approved Publishers:
    • Ops Golden AMI Account: 123456738923
    • InfoBlox: 111122223333
    • Terraform Enterprise: 444455556666
    
    🚫 Custom AMI Policy:
    App teams are NOT allowed to build/bake custom AMIs.
    All customization must be done via user-data scripts at launch time.
    
    📝 Exception Request Process:
    1. Submit ServiceNow ticket: SNOW-CATALOG-AMI-EXCEPTION
    2. Provide business justification and security review
    3. Specify account ID and duration (max 90 days)
    4. Obtain approvals from:
       - Application Security Team
       - Platform Engineering Team
       - Chief Architect (for >30 day exceptions)
    
    ⏱️ SLA: 5 business days for exception approval
    
    📞 Support: platform-team@company.com | Slack: #ami-governance
  EOT
  
  tags = {
    Environment  = "production"
    Phase        = "enforcement"
    Owner        = "platform-team"
    CostCenter   = "IT-Security"
    Compliance   = "Required"
    ReviewDate   = "2026-06-01"
  }
}

# SNS subscription for expiry notifications
resource "aws_sns_topic_subscription" "ami_exception_expiry_email" {
  topic_arn = module.ami_governance_production.exception_expiry_sns_topic_arn
  protocol  = "email"
  endpoint  = "platform-team@company.com"
}

# CloudWatch metric alarm for policy violations
resource "aws_cloudwatch_metric_alarm" "ami_policy_violations" {
  alarm_name          = "ami-governance-policy-violations"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "PolicyDenials"
  namespace           = "AWS/Organizations"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when more than 10 AMI policy denials occur in 5 minutes"
  alarm_actions       = [module.ami_governance_production.exception_expiry_sns_topic_arn]
  
  dimensions = {
    PolicyType = "AMI-Governance"
  }
}
```

## Outputs

```bash
terraform output -json > ami-governance-outputs.json

# View policy summary
terraform output policy_summary

# Check active exceptions
terraform output active_exceptions

# View expired exceptions (should be removed)
terraform output expired_exceptions
```

## Post-Deployment Validation

```bash
# Test from a workload account
aws ec2 run-instances \
  --image-id ami-unauthorized123 \
  --instance-type t3.micro \
  --region us-east-1

# Expected: Denied with exception message

# Test with approved AMI
aws ec2 run-instances \
  --image-id ami-approved456 \
  --instance-type t3.micro \
  --region us-east-1

# Expected: Success
```
