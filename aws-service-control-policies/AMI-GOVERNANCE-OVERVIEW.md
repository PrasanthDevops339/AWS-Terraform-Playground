# AMI Governance Controls - Implementation Overview

**Last Updated**: 2026-02-11
**Version**: 2026-01-18
**Status**: Production Ready

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Policy Files](#policy-files)
4. [Approved AMI Catalog](#approved-ami-catalog)
5. [Template Variables](#template-variables)
6. [AMI Age and Deprecation Controls](#ami-age-and-deprecation-controls)
7. [Deployment Strategy](#deployment-strategy)
8. [Monitoring and Validation](#monitoring-and-validation)

---

## Overview

The AMI Governance Controls system enforces centralized control over which Amazon Machine Images (AMIs) can be used to launch EC2 instances across the AWS Organization. This implementation uses a **defense-in-depth approach** with two enforcement layers:

### Enforcement Layers

1. **Declarative Policy (Primary)** - `declarative-policy-ec2-2026-01-18.json`
   - Enforced at the EC2 service control plane level
   - Cannot be overridden by account administrators
   - Supports audit mode for testing before enforcement
   - Provides custom error messages to users
   - **Enforces AMI freshness (< 300 days old)**
   - **Blocks deprecated AMIs (0 days tolerance)**

2. **Service Control Policy (Secondary)** - `scp-ami-guardrail-2026-01-18.json`
   - IAM-based authorization boundary
   - Always enforced (no audit mode)
   - Provides backup enforcement if declarative policy fails
   - Prevents AMI creation and public sharing

### Key Benefits

- ✅ **Service-Level Enforcement**: Policies enforce at the EC2 service level, preventing account-level overrides
- ✅ **Phased Rollout**: Audit mode allows testing and impact assessment before full enforcement
- ✅ **AMI Freshness**: Hardcoded 300-day maximum age ensures patch currency
- ✅ **Deprecation Protection**: Zero tolerance for deprecated AMIs
- ✅ **Infrastructure as Code**: Complete Terraform implementation for version control and repeatability
- ✅ **Defense in Depth**: Dual-layer enforcement ensures no single point of failure

---

## Architecture

### High-Level Flow

```
Developer Launches EC2 Instance
         ↓
   EC2 API Request
         ↓
┌────────────────────────────────┐
│ Declarative Policy (Layer 1)  │ ← Primary enforcement
│ Checks:                        │
│  • AMI owner account          │
│  • AMI age (< 300 days)       │
│  • AMI deprecation status     │
└────────────────────────────────┘
         ↓
   All Checks Pass?
         ↓
    ┌────┴────┐
   No        Yes
    ↓          ↓
  DENY    ┌────────────────────────┐
          │ SCP Check (Layer 2)    │ ← Secondary enforcement
          │ • IAM boundary check   │
          │ • Owner verification   │
          └────────────────────────┘
                  ↓
            AMI Approved?
                  ↓
             ┌────┴────┐
            No        Yes
             ↓          ↓
           DENY      ALLOW
```

### Prasa Operations Accounts

The following accounts are authorized to publish approved AMIs:

| Account ID    | Account Alias                     | Environment | Region     |
|---------------|-----------------------------------|-------------|------------|
| 565656565656  | prasains-operations-dev-use2      | DEV         | us-east-2  |
| 666363636363  | prasains-operations-prd-use2      | PRD         | us-east-2  |

---

## Policy Files

### 1. Declarative Policy - `declarative-policy-ec2-2026-01-18.json`

**Purpose**: Primary enforcement mechanism at the EC2 service level

**Key Features**:
- Blocks public AMI sharing (`block_new_sharing`)
- Enforces approved AMI publisher accounts
- **Hardcoded AMI age control: 300 days maximum**
- **Hardcoded deprecation control: 0 days (no deprecated AMIs)**
- Supports template variables for dynamic configuration
- Provides custom exception messages

**Enforcement Modes**:
- `audit_mode` - Logs violations without blocking (for testing)
- `enabled` - Actively blocks non-compliant AMI launches

**Structure**:
```json
{
  "ec2_attributes": {
    "image_block_public_access": {
      "state": "block_new_sharing"
    },
    "allowed_images_settings": {
      "state": "${enforcement_mode}",
      "image_criteria": {
        "criteria_1": {
          "allowed_image_providers": [...],
          "creation_date_condition": {
            "maximum_days_since_created": 300
          },
          "deprecation_time_condition": {
            "maximum_days_since_deprecated": 0
          }
        }
      },
      "exception_message": "..."
    }
  }
}
```

### 2. Service Control Policy - `scp-ami-guardrail-2026-01-18.json`

**Purpose**: Secondary enforcement via IAM permission boundary

**Key Features**:
- Always enforced (no audit mode)
- Three protection statements:
  1. **DenyEC2LaunchWithNonApprovedAMIs** - Blocks launching instances from non-approved AMIs
  2. **DenyAMICreationAndSideload** - Prevents creating/importing custom AMIs
  3. **DenyPublicAMISharing** - Blocks making AMIs publicly accessible

**Actions Protected**:
- `ec2:RunInstances`
- `ec2:CreateFleet`
- `ec2:RequestSpotInstances`
- `ec2:RunScheduledInstances`
- `ec2:CreateImage`
- `ec2:CopyImage`
- `ec2:RegisterImage`
- `ec2:ImportImage`
- `ec2:ModifyImageAttribute` (when making public)

---

## Approved AMI Catalog

### Category 1: Marketplace Customized AMIs

**MarkLogic AMIs** (from AWS Marketplace, customized for Prasa):

| AMI Name Pattern          | Alias                   | Base          | OS              |
|---------------------------|-------------------------|---------------|-----------------|
| `prasa-opsdir-mlal2-*`    | prasa-OPSDIR-MLAL2-CF   | MarkLogic     | Amazon Linux 2  |
| `prasa-mlal2-*`           | prasa-MLAL2-CF          | MarkLogic     | Amazon Linux 2  |

### Category 2: Prasa Customized AMIs

**AWS Base Images** (customized by Prasa Operations team):

| AMI Name Pattern          | Alias                   | Operating System          |
|---------------------------|-------------------------|---------------------------|
| `prasa-rhel8-*`           | prasa-rhel8-cf          | Red Hat Enterprise Linux 8|
| `prasa-rhel9-*`           | prasa-rhel9-cf          | Red Hat Enterprise Linux 9|
| `prasa-win16-*`           | prasa-win16-cf          | Windows Server 2016       |
| `prasa-win19-*`           | prasa-win19-cf          | Windows Server 2019       |
| `prasa-win22-*`           | prasa-win22-cf          | Windows Server 2022       |
| `prasa-al2023-*`          | prasa-al2023-cf         | Amazon Linux 2023         |
| `prasa-al2-2024-*`        | prasa-al2-2024-cf       | Amazon Linux 2 (2024)     |

---

## Configuration Approach

The AMI governance implementation uses a **mostly hardcoded approach** for simplicity and reliability:

### Hardcoded Values (In JSON Policy Files)

The following values are **hardcoded directly** in the policy JSON files:

| Component                    | Value                                                | Location                               |
|------------------------------|------------------------------------------------------|----------------------------------------|
| **Prasa Operations Accounts**| `565656565656`, `666363636363`                       | Both policy files                      |
| **AMI Age Limit**            | 300 days                                             | Declarative policy                     |
| **Deprecation Tolerance**    | 0 days (immediate block)                             | Declarative policy                     |
| **AMI Name Patterns**        | `prasa-rhel8-*`, `prasa-rhel9-*`, etc.              | Declarative policy exception message   |
| **Exception Request URL**    | `https://jira.example.com/servicedesk/ami-exception` | Declarative policy exception message   |
| **Exception Durations**      | 365 days (AMI), 90 days (other)                     | Declarative policy exception message   |

### Single Template Variable

Only **one template variable** remains for runtime configuration:

| Variable           | Type   | Description                     | Values                        | Used In             |
|--------------------|--------|---------------------------------|-------------------------------|---------------------|
| `enforcement_mode` | string | Policy enforcement mode         | `"audit_mode"` or `"enabled"` | Declarative policy  |

### Module Invocation Examples

**Service Control Policy** (completely hardcoded, no template variables):
```hcl
module "scp-ami-guardrail" {
  source      = "../../modules/organizations"
  policy_name = "scp-ami-guardrail"
  file_date   = "2026-01-18"
  type        = "SERVICE_CONTROL_POLICY"
  target_ids  = [var.workloads, var.sandbox]
  # No policy_vars needed - everything hardcoded in JSON
}
```

**Declarative Policy** (only enforcement_mode configurable):
```hcl
module "declarative-policy-ec2" {
  source      = "../../modules/organizations"
  policy_name = "declarative-policy-ec2"
  file_date   = "2026-01-18"
  type        = "DECLARATIVE_POLICY_EC2"
  target_ids  = [var.workloads, var.sandbox]

  policy_vars = {
    enforcement_mode = "audit_mode"  # Only variable
  }
}
```

### Benefits of Hardcoding

| Benefit                     | Description                                                    |
|-----------------------------|----------------------------------------------------------------|
| **Simplicity**              | No complex variable management or template logic               |
| **Consistency**             | Same values enforced across all environments                   |
| **Reliability**             | Fewer moving parts, less chance of misconfiguration           |
| **Auditability**            | All controls visible directly in policy files                  |
| **Version Control**         | Changes to values require explicit policy file updates         |

---

## AMI Age and Deprecation Controls

### Hardcoded Enforcement Rules

The declarative policy includes **hardcoded** AMI freshness and deprecation controls:

#### 1. AMI Age Limit: 300 Days

```json
"creation_date_condition": {
  "maximum_days_since_created": 300
}
```

**What this means:**
- ✅ AMIs must be created within the last 300 days
- ❌ AMIs older than 300 days are automatically blocked
- 🎯 **Purpose**: Ensures instances use recently patched and updated images

**Example Scenarios:**
- AMI created on 2025-11-01, launched on 2026-02-11: ✅ **Allowed** (102 days old)
- AMI created on 2025-04-01, launched on 2026-02-11: ❌ **Blocked** (316 days old)

#### 2. Deprecation Protection: Immediate Block

```json
"deprecation_time_condition": {
  "maximum_days_since_deprecated": 0
}
```

**What this means:**
- ✅ Only non-deprecated AMIs are allowed
- ❌ Deprecated AMIs are immediately blocked (0 days grace period)
- 🎯 **Purpose**: Prevents use of AMIs marked as deprecated by Prasa Operations

**Example Scenarios:**
- AMI is active (not deprecated): ✅ **Allowed**
- AMI deprecated yesterday: ❌ **Blocked**
- AMI deprecated 30 days ago: ❌ **Blocked**

### Why These Values?

| Control                        | Value    | Rationale                                                          |
|--------------------------------|----------|--------------------------------------------------------------------|
| Maximum AMI Age                | 300 days | ~10 months ensures quarterly security patching is enforced        |
| Maximum Days Since Deprecated  | 0 days   | Zero tolerance for deprecated AMIs ensures immediate compliance   |

### Compliance Requirements

For an AMI to be approved for launching instances, it must meet **all** of these criteria:

1. ✅ **Owner Account**: Must be from Prasa Operations (565656565656 or 666363636363)
2. ✅ **Age**: Must be less than 300 days old
3. ✅ **Status**: Must NOT be deprecated
4. ✅ **Naming**: Must follow approved naming patterns (prasa-*)

**All four conditions are enforced simultaneously.**

---

## Deployment Strategy

### Phase 1: Development Environment Testing

1. Deploy to dev environment with `enforcement_mode = "audit_mode"`
2. Monitor CloudTrail logs for policy evaluations
3. Validate effective policies on test accounts
4. Test approved and non-approved AMI launches
5. Verify AMI age and deprecation controls

### Phase 2: Production Audit Mode

1. Deploy to production OUs with `enforcement_mode = "audit_mode"`
2. Run for 2-4 weeks to assess impact
3. Query CloudTrail for `imageAllowed=false` indicators
4. Identify non-compliant workloads:
   - AMIs older than 300 days
   - Deprecated AMIs
   - AMIs from non-approved owners
5. Work with teams to migrate to compliant AMIs

### Phase 3: Production Enforcement

1. Verify all non-compliant usage addressed
2. Switch to `enforcement_mode = "enabled"`
3. Monitor for blocked launches
4. Respond to user questions about blocks

### Target Organizational Units

**Production** (`environments/prd/main.tf`):
- Target OUs: `var.workloads`, `var.sandbox`
- Enforcement Mode: `audit_mode` (initial rollout)

**Development** (`environments/dev/main.tf`):
- Target OUs: `var.workloads`
- Enforcement Mode: `audit_mode`

---

## Monitoring and Validation

### Verify Policy Attachments

```bash
# List policies attached to an OU or account
aws organizations list-policies-for-target \
  --target-id ou-xxxx-xxxxxxxx \
  --filter DECLARATIVE_POLICY_EC2

aws organizations list-policies-for-target \
  --target-id ou-xxxx-xxxxxxxx \
  --filter SERVICE_CONTROL_POLICY
```

### Check Effective Policies

```bash
# View effective declarative policy on an account
aws organizations describe-effective-policy \
  --policy-type DECLARATIVE_POLICY_EC2 \
  --target-id 123456789012

# View effective SCP on an account
aws organizations describe-effective-policy \
  --policy-type SERVICE_CONTROL_POLICY \
  --target-id 123456789012
```

### Monitor CloudTrail Logs

**Audit Mode Monitoring**:
```bash
# Find RunInstances events with imageAllowed indicators
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-results 50

# Look for imageAllowed=false in the event details
```

**Enforcement Mode Monitoring**:
```bash
# Find denied EC2 launch attempts
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --max-results 50 | jq '.Events[] | select(.CloudTrailEvent | contains("AccessDenied"))'
```

### Common Validation Commands

```bash
# Verify Terraform configuration
terraform init
terraform validate
terraform plan

# Apply changes
terraform apply
```

---

## Error Messages and Troubleshooting

### User-Facing Error Message

When a launch is blocked, users see:

```
AMI not approved for use in this organization.

Only images from Prasa Operations accounts are permitted:
  - 565656565656: prasains-operations-dev-use2
  - 666363636363: prasains-operations-prd-use2

Approved AMI patterns:
  - prasa-rhel8-*
  - prasa-rhel9-*
  - prasa-win16-*
  - prasa-win19-*
  - prasa-win22-*
  - prasa-al2023-*
  - prasa-al2-2024-*
  - prasa-opsdir-mlal2-*
  - prasa-mlal2-*

To request an exception, submit a ticket at: https://jira.example.com/servicedesk/ami-exception

Exception durations:
  - Up to 365 days for exception AMIs
  - Up to 90 days for other exceptions
```

### Common Issues

| Issue                          | Cause                                  | Solution                                              |
|--------------------------------|----------------------------------------|-------------------------------------------------------|
| Approved AMI launch blocked    | AMI is older than 300 days            | Use a newer AMI from Prasa Operations                 |
| Approved AMI launch blocked    | AMI has been deprecated               | Use a non-deprecated AMI from Prasa Operations        |
| Approved AMI launch blocked    | AMI owner account not in allowlist    | Verify AMI is from 565656565656 or 666363636363      |
| Cannot create custom AMI       | SCP denies AMI creation               | Expected - only Ops accounts can create AMIs          |
| Cannot make AMI public         | SCP denies public sharing             | Expected - public sharing is blocked                  |

---

## Repository Structure

```
aws-service-control-policies/
├── environments/
│   ├── dev/
│   │   └── main.tf              # Dev environment config
│   └── prd/
│       └── main.tf              # Production environment config
├── modules/
│   └── organizations/
│       ├── main.tf              # Core module logic (simplified)
│       ├── variables.tf         # Module variables
│       └── outputs.tf           # Module outputs
├── policies/
│   ├── declarative-policy-ec2-2026-01-18.json    # Cleaned policy
│   └── scp-ami-guardrail-2026-01-18.json         # Cleaned policy
├── AMI-GOVERNANCE-OVERVIEW.md   # This documentation
└── FIXES-APPLIED.md             # Change log
```

---

## Next Steps

1. ✅ Clean policy JSON files (remove all comments)
2. ✅ Create documentation (this file)
3. ✅ Update environment configurations with Prasa account IDs
4. ✅ Hardcode AMI age and deprecation controls
5. ✅ Simplify module (remove exception expiry complexity)
6. ⏳ Test in dev environment
7. ⏳ Deploy to production in audit mode
8. ⏳ Monitor and validate
9. ⏳ Switch to enforcement mode

---

## Additional Resources

- **Change Log**: See `FIXES-APPLIED.md` for detailed change history
- **Task Plan**: See `AWS-Terraform-Playground/task.md` for implementation tasks
- **Design Document**: See `AWS-Terraform-Playground/design.md` for architecture details
- **AWS Documentation**:
  - [EC2 Declarative Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html)
  - [EC2 Allowed AMIs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-allowed-amis.html)

---

**Document Maintainer**: Cloud Platform Team
**Last Review Date**: 2026-02-11
**Status**: ✅ Production Ready
