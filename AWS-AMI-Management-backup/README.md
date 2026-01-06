# AMI Governance Guardrail

**Enterprise-grade AMI governance for AWS Organizations**

[![GitLab CI](https://img.shields.io/badge/gitlab%20ci-passing-brightgreen)](/.gitlab-ci.yml)
[![Python 3.9+](https://img.shields.io/badge/python-3.9+-blue.svg)](https://www.python.org/downloads/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## 🎯 Overview

This repository provides a **production-ready AMI governance framework** for AWS Organizations. It enforces:

✅ **Golden AMI Allowlist** - Only approved AMI publisher accounts can be used to launch EC2 instances  
✅ **No AMI Creation/Sideload** - Workload accounts cannot create, copy, register, or import AMIs  
✅ **No Public AMI Sharing** - Prevents new public AMI sharing across the organization  
✅ **Time-Bound Exceptions** - Temporary exceptions with automatic expiry tracking  

### Key Features

- **Dual-Layer Enforcement** - Declarative Policy + SCP for defense-in-depth
- **GitOps Workflow** - Configuration as code with automated validation
- **Single Source of Truth** - All allowlist accounts managed in one JSON file
- **CI/CD Integration** - Automated policy generation and validation
- **Exception Management** - Built-in exception request and approval workflow
- **Production Ready** - Comprehensive runbooks and architecture documentation

---

## 🏗️ Architecture
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

```
┌─────────────────────────────────────────────────────────────────┐
│              AWS ORGANIZATION ROOT                              │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Declarative Policy (EC2)                                  │  │
│  │ • Block public AMI sharing                                │  │
│  │ • Enforce AMI publisher allowlist                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Service Control Policy (SCP)                              │  │
│  │ • Deny non-approved AMI launches                          │  │
│  │ • Deny AMI creation/copy/import                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
└───────────────────────┬─────────────────────────────────────────┘
                        │
        ┌───────────────┴────────────┬────────────────┐
        ▼                            ▼                ▼
   ┌─────────┐                  ┌─────────┐     ┌─────────┐
   │Workload │                  │Workload │     │Workload │
   │   OU    │                  │   OU    │     │   OU    │
   └─────────┘                  └─────────┘     └─────────┘
```

**See [docs/architecture.md](docs/architecture.md) for detailed design**

---

## 📁 Repository Structure

```
.
├── config/
│   └── ami_publishers.json          # Single source of truth for allowlist
├── scripts/
│   ├── generate_policies.py         # Policy generator (Python)
│   └── validate_policies.py         # Configuration validator
├── dist/                             # Generated policies (output)
│   ├── declarative-policy-ec2.json
│   └── scp-ami-guardrail.json
├── docs/
│   ├── runbook-ami-governance.md    # Operational procedures
│   └── architecture.md              # HLD/LLD diagrams
├── .gitlab-ci.yml                   # CI/CD pipeline
└── README.md                        # This file
```

---

## 🚀 Quick Start

### Prerequisites

- Python 3.9 or higher
- AWS CLI configured with Organizations admin access
- Git access to this repository

### 1. Review Configuration

Edit the allowlist configuration:

```bash
vi config/ami_publishers.json
```

**Example structure:**

```json
{
  "ops_publisher_account": {
    "account_id": "123456738923",
    "description": "Operations golden AMI publisher"
  },
  "vendor_publisher_accounts": [
    {
      "account_id": "111122223333",
      "vendor_name": "InfoBlox"
    }
  ],
  "exception_accounts": [
    {
      "account_id": "777788889999",
      "expires_on": "2026-02-28",
      "reason": "Migration from legacy pipeline",
      "ticket": "CLOUD-1234"
    }
  ]
}
```

### 2. Generate Policies

```bash
# Generate in audit mode (recommended first deployment)
python scripts/generate_policies.py --mode audit_mode

# Or generate in enforcement mode
python scripts/generate_policies.py --mode enabled
```

**Output:**
```
======================================================================
AMI GOVERNANCE POLICY GENERATOR
======================================================================
Config: config/ami_publishers.json
Enforcement Mode: audit_mode
Generated: 2026-01-03T10:30:00Z
======================================================================

Building active allowlist...
✓ Active exception: 777788889999 (expires 2026-02-28) - Migration

======================================================================
ACTIVE ALLOWLIST SUMMARY
======================================================================
Total approved accounts: 4
Accounts: 111122223333, 123456738923, 222233334444, 777788889999
======================================================================

✓ Generated: dist/declarative-policy-ec2.json
✓ Generated: dist/scp-ami-guardrail.json
✓ Allowlist consistency verified
✓ Policy generation complete!
```

### 3. Validate Policies

```bash
python scripts/validate_policies.py
```

**Output:**
```
======================================================================
VALIDATING CONFIGURATION
======================================================================
✓ Valid JSON format: config/ami_publishers.json
✓ All required fields present
✓ Ops publisher: 123456738923
✓ Vendor publishers: 2
  ✓ Active exception: 777788889999 expires 2026-02-28
✓ Active exceptions: 1

======================================================================
VALIDATING GENERATED POLICIES
======================================================================
✓ Valid JSON: dist/declarative-policy-ec2.json
✓ Valid JSON: dist/scp-ami-guardrail.json
✓ Allowlist consistency verified
  Total approved accounts: 4
  Accounts: 111122223333, 123456738923, 222233334444, 777788889999
✓ Enforcement mode: audit_mode
✓ Public AMI blocking: block_new_sharing

======================================================================
✅ VALIDATION PASSED
======================================================================
```

### 4. Apply Policies to AWS Organizations

**⚠️ IMPORTANT:** Deploy in **audit mode first**, monitor for 2-4 weeks, then switch to enforcement mode.

#### Option A: AWS Console (Recommended)

1. **Navigate to AWS Organizations Console**
   - URL: https://console.aws.amazon.com/organizations/v2/home/policies

2. **Create Declarative Policy**
   - Go to: **Policies → Declarative policies for EC2 → Create policy**
   - Name: `ami-governance-declarative-policy`
   - Content: Copy from `dist/declarative-policy-ec2.json`
   - Attach to: **Root**

3. **Create and Attach SCP**
   - Go to: **Policies → Service control policies → Create policy**
   - Name: `scp-ami-guardrail`
   - Content: Copy from `dist/scp-ami-guardrail.json`
   - **Update `o-placeholder` with your Org ID**
   - Attach to: **Root**

**See [docs/runbook-ami-governance.md](docs/runbook-ami-governance.md) for detailed step-by-step instructions**

#### Option B: AWS CLI

```bash
# Get your organization root ID
ORG_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)

echo "Organization Root: $ORG_ROOT_ID"
echo "Organization ID: $ORG_ID"

# Update SCP with your org ID
sed "s/o-placeholder/$ORG_ID/g" dist/scp-ami-guardrail.json > dist/scp-ami-guardrail-final.json

# Create and attach declarative policy
DECL_POLICY_ID=$(aws organizations create-policy \
  --content file://dist/declarative-policy-ec2.json \
  --description "AMI Governance - Restrict EC2 launches to approved publishers" \
  --name "ami-governance-declarative-policy" \
  --type DECLARATIVE_POLICY_EC2 \
  --query 'Policy.PolicySummary.Id' \
  --output text)

aws organizations attach-policy \
  --policy-id "$DECL_POLICY_ID" \
  --target-id "$ORG_ROOT_ID"

echo "✓ Declarative policy attached: $DECL_POLICY_ID"

# Create and attach SCP
SCP_POLICY_ID=$(aws organizations create-policy \
  --content file://dist/scp-ami-guardrail-final.json \
  --description "AMI Governance SCP" \
  --name "scp-ami-guardrail" \
  --type SERVICE_CONTROL_POLICY \
  --query 'Policy.PolicySummary.Id' \
  --output text)

aws organizations attach-policy \
  --policy-id "$SCP_POLICY_ID" \
  --target-id "$ORG_ROOT_ID"

echo "✓ SCP attached: $SCP_POLICY_ID"
```

### 5. Verify Enforcement

Test with an approved AMI (should succeed):

```bash
aws ec2 run-instances \
  --image-id ami-from-approved-account \
  --instance-type t3.micro \
  --dry-run
```

Test with a non-approved AMI (should fail in enforcement mode):

```bash
aws ec2 run-instances \
  --image-id ami-from-random-account \
  --instance-type t3.micro \
  --dry-run
```

**Expected error (enforcement mode):**
```
An error occurred (UnauthorizedException): AMI not approved for use in this organization.
Only images from approved publisher accounts are permitted.
```

---

## 📋 Exception Request Process

### When to Request an Exception

Exceptions are granted for:
- **Migration scenarios** - Transitioning from legacy image pipelines (max 90 days)
- **Vendor POC/pilot** - Testing new vendor products (max 60 days)
- **Emergency response** - Security patching or incident response (max 30 days)

### How to Request

1. **Create a ticket** (JIRA, ServiceNow, etc.) with:
   - AWS Account ID
   - Business justification
   - Duration requested (max 90 days)
   - Migration/exit plan
   - Technical contact
   - Sponsor name

2. **Obtain approvals:**
   - Security Lead + Cloud Architect (migration)
   - Engineering Manager + CTO (vendor POC)
   - Security Lead + VP Engineering (emergency)

3. **Submit to Cloud Platform Team** via email or Slack

### Implementation

Once approved, the Cloud Platform Team will:

1. Create a feature branch
2. Add exception to `config/ami_publishers.json`:
   ```json
   {
     "account_id": "123456789012",
     "expires_on": "2026-04-15",
     "reason": "Migration from legacy pipeline",
     "ticket": "CLOUD-1234",
     "requested_by": "app-team-alpha",
     "approved_by": "security-lead",
     "approval_date": "2026-01-03"
   }
   ```
3. Generate and validate policies
4. Create merge request
5. Deploy updated policies to AWS Organizations

**See [docs/runbook-ami-governance.md](docs/runbook-ami-governance.md#exception-request-process) for complete workflow**

---
## 🔄 CI/CD Pipeline

The GitLab CI pipeline automatically validates configuration on every commit:

### Pipeline Stages

1. **validate:config** - Validates JSON format and checks for expired exceptions
2. **generate:policies:audit** - Generates policies in audit mode
3. **verify:policies** - Verifies allowlist consistency between policies
4. **scheduled:expiry-check** - Daily check for expiring exceptions (14-day warning)

### Pipeline Configuration

```yaml
stages:
  - validate
  - generate
  - verify

validate:config:
  script:
    - python scripts/validate_policies.py
  rules:
    - if: '$CI_PIPELINE_SOURCE == "push"'
```

**See [.gitlab-ci.yml](.gitlab-ci.yml) for complete pipeline definition**

---

## 🛡️ Security Considerations

### Defense-in-Depth

This framework uses **two enforcement layers**:

1. **Declarative Policy (EC2)** - Native AWS Organizations control for EC2 image restrictions
2. **Service Control Policy (SCP)** - IAM permission boundary preventing policy bypass

Both policies derive from the same source of truth (`config/ami_publishers.json`) and are validated for consistency in CI.

### Threat Mitigations

| Threat | Mitigation |
|--------|------------|
| Developers launching vulnerable AMIs | Allowlist enforcement blocks non-approved AMIs |
| Custom AMI creation to bypass controls | SCP denies all AMI creation operations |
| AMI sharing for lateral movement | SCP blocks public AMI sharing |
| Child OU policy override | `@@operators_allowed_for_child_policies: ["@@none"]` |
| Stale exceptions | Daily CI checks fail on expired exceptions |
| Configuration drift | GitOps enforces config-as-code |

### Compliance Mappings

- **CIS AWS Benchmark 5.1** - No hardcoded credentials in AMIs
- **SOC 2 CC6.6** - Use of approved vendors
- **NIST 800-53 CM-2** - Baseline configuration management
- **ISO 27001 A.12.5.1** - Software installation controls

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [docs/runbook-ami-governance.md](docs/runbook-ami-governance.md) | Complete operational runbook with step-by-step procedures |
| [docs/architecture.md](docs/architecture.md) | High-level and low-level design with diagrams |
| [config/ami_publishers.json](config/ami_publishers.json) | Configuration file schema and examples |
| [.gitlab-ci.yml](.gitlab-ci.yml) | CI/CD pipeline configuration |

---

## 🔧 Maintenance

### Daily Automated Checks

The CI pipeline runs daily to check for:
- Expired exceptions (fails if found)
- Expiring exceptions within 14 days (warning)
- Configuration consistency

### Monthly Reviews

Recommended monthly tasks:
- Review active exceptions and renewal requests
- Audit CloudTrail logs for policy violations
- Update vendor publisher list as needed
- Review and update golden AMI catalog

### Annual Reviews

- Complete policy effectiveness review
- Update threat model and mitigations
- Review and update exception approval matrix
- Compliance audit of AMI governance controls

---

## 🐛 Troubleshooting

### Common Issues

**Issue: CI fails with "Expired exception found"**

**Solution:** Remove or extend the expired exception in `config/ami_publishers.json`

```bash
# Remove expired exception or update expires_on date
vi config/ami_publishers.json

# Regenerate policies
python scripts/generate_policies.py

# Commit changes
git commit -am "fix: Remove expired exception ACCOUNT_ID"
```

---

**Issue: "Allowlist mismatch" validation error**

**Solution:** Regenerate policies from config

```bash
python scripts/generate_policies.py
python scripts/validate_policies.py
```

---

**Issue: Legitimate workload blocked after enforcement**

**Solution:** Either:
1. Request exception (temporary)
2. Migrate workload to golden AMI (permanent)
3. Revert to audit mode temporarily

**See [docs/runbook-ami-governance.md#troubleshooting](docs/runbook-ami-governance.md#troubleshooting) for more solutions**

---

## 👥 Contacts

| Issue Type | Contact | SLA |
|------------|---------|-----|
| Exception Requests | cloud-platform-team@company.com | 2 business days |
| Policy Failures | Slack: #cloud-platform-oncall | 15 minutes |
| Security Concerns | security-team@company.com | 1 hour |
| General Questions | Slack: #cloud-platform-help | 4 hours |

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- AWS Organizations team for declarative policy support
- HashiCorp for infrastructure-as-code best practices
- Cloud platform engineering community

---

## 📈 Roadmap

- [ ] Add GitHub Actions support (in addition to GitLab CI)
- [ ] Terraform module for automated policy deployment
- [ ] SNS notifications for exception expiry warnings
- [ ] CloudWatch dashboard for policy compliance metrics
- [ ] Automated remediation for already-public AMIs

---

## 🔗 Related Resources

- [AWS Organizations Declarative Policies Documentation](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html)
- [AWS Service Control Policies Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [EC2 Image Block Public Access](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/sharingamis-intro.html#block-public-access-to-amis)

---

**Need help? Contact the Cloud Platform Team!**

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
