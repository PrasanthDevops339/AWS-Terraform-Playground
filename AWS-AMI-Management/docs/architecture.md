# AMI Governance Architecture

**Version:** 1.0  
**Last Updated:** 2026-01-03  
**Owner:** Cloud Platform Team

---

## Table of Contents

1. [High-Level Design (HLD)](#high-level-design-hld)
2. [Low-Level Design (LLD)](#low-level-design-lld)
3. [Policy Enforcement Flow](#policy-enforcement-flow)
4. [Exception Management](#exception-management)
5. [Deployment Architecture](#deployment-architecture)

---

## High-Level Design (HLD)

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                      AWS ORGANIZATION ROOT                          │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Declarative Policy (EC2)                                   │    │
│  │  • Block new public AMI sharing                             │    │
│  │  • Enforce allowed AMI publishers                           │    │
│  │  • Modes: audit_mode | enabled                              │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Service Control Policy (SCP)                               │    │
│  │  • Deny EC2 launch with non-approved AMIs                   │    │
│  │  • Deny AMI creation/sideload operations                    │    │
│  │  • Deny public AMI sharing                                  │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                       │
└───────────────────────┬───────────────────────────────────────────┬─┘
                        │                                           │
        ┌───────────────┴────────────┐                 ┌───────────┴──────────┐
        │                              │                 │                       │
        ▼                              ▼                 ▼                       ▼
┌──────────────┐            ┌──────────────┐   ┌──────────────┐      ┌──────────────┐
│ Workload OU  │            │ Workload OU  │   │ Workload OU  │      │ Workload OU  │
│  (Dev/Test)  │            │ (Production) │   │  (Sandbox)   │      │  (Security)  │
│              │            │              │   │              │      │              │
│ ┌──────────┐ │            │ ┌──────────┐ │   │ ┌──────────┐ │      │ ┌──────────┐ │
│ │ Account  │ │            │ │ Account  │ │   │ │ Account  │ │      │ │ Account  │ │
│ │ 1111... │ │            │ │ 4444... │ │   │ │ 7777... │ │      │ │ 2222... │ │
│ └──────────┘ │            │ └──────────┘ │   │ └──────────┘ │      │ └──────────┘ │
│              │            │              │   │              │      │              │
│ ✓ Can launch │            │ ✓ Can launch │   │ ✓ Can launch │      │ ✓ Can launch │
│   approved   │            │   approved   │   │   approved   │      │   approved   │
│   AMIs only  │            │   AMIs only  │   │   AMIs only  │      │   AMIs only  │
│              │            │              │   │              │      │              │
│ ✗ Cannot     │            │ ✗ Cannot     │   │ ✗ Cannot     │      │ ✗ Cannot     │
│   create AMI │            │   create AMI │   │   create AMI │      │   create AMI │
└──────────────┘            └──────────────┘   └──────────────┘      └──────────────┘


┌─────────────────────────────────────────────────────────────────────┐
│                   APPROVED AMI PUBLISHERS                            │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Ops Golden AMI Publisher (123456738923)                    │    │
│  │  • Hardened base images                                     │    │
│  │  • Regular security patches                                 │    │
│  │  • Compliance validated                                     │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Vendor Publishers                                          │    │
│  │  • InfoBlox (111122223333)                                  │    │
│  │  • Terraform Enterprise (444455556666)                      │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Exception Accounts (Time-Bound)                            │    │
│  │  • Account 777788889999 - expires 2026-02-28               │    │
│  │  • Account 222233334444 - expires 2026-03-15               │    │
│  └────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. Policy Enforcement (Dual-Layer)

**Declarative Policy (Layer 1)**
- AWS Organizations native policy for EC2
- Controls image attributes at resource level
- Provides user-friendly exception messages
- Supports audit mode for validation

**Service Control Policy (Layer 2)**
- IAM permission boundary
- Blocks operations at API level
- Defense-in-depth against policy bypass
- Prevents privilege escalation

#### 2. Source of Truth

**config/ami_publishers.json**
- Single authoritative source for allowlist
- Version controlled in Git
- CI validation on every change
- Enforces time-bound exceptions

#### 3. Policy Generation Pipeline

```
config/ami_publishers.json
         │
         ├─► Active Exception Filter (expires_on >= today)
         │
         ├─► generate_policies.py
         │
         ├─► dist/declarative-policy-ec2.json
         │
         └─► dist/scp-ami-guardrail.json
                (identical allowlists)
```

### Design Principles

1. **Defense in Depth** - Two enforcement layers prevent single point of failure
2. **Least Privilege** - Workload accounts cannot create AMIs
3. **Time-Bound Exceptions** - All exceptions automatically expire
4. **Automated Validation** - CI pipeline ensures consistency
5. **Audit Trail** - All changes tracked in Git + CloudTrail

---

## Low-Level Design (LLD)

### Component Details

#### 1. Configuration Schema

**config/ami_publishers.json structure:**

```json
{
  "ops_publisher_account": {
    "account_id": "123456738923",
    "description": "...",
    "purpose": "..."
  },
  
  "vendor_publisher_accounts": [
    {
      "account_id": "111122223333",
      "vendor_name": "InfoBlox",
      "description": "...",
      "business_justification": "..."
    }
  ],
  
  "exception_accounts": [
    {
      "account_id": "777788889999",
      "expires_on": "2026-02-28",  // ISO 8601 date
      "reason": "...",
      "ticket": "CLOUD-1234",
      "requested_by": "...",
      "approved_by": "...",
      "approval_date": "...",
      "notes": "..."
    }
  ],
  
  "policy_config": {
    "enforcement_mode": "audit_mode" | "enabled",
    "block_public_ami_sharing": true,
    "deny_ami_creation_in_workloads": true
  }
}
```

#### 2. Declarative Policy Structure

**dist/declarative-policy-ec2.json:**

```json
{
  "content": {
    "ec2": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      
      "ec2_attributes": {
        "image_block_public_access": {
          "@@operators_allowed_for_child_policies": ["@@none"],
          "state": "block_new_sharing"
        },
        
        "allowed_images_settings": {
          "@@operators_allowed_for_child_policies": ["@@none"],
          "state": "audit_mode" | "enabled",
          
          "image_criteria": {
            "criteria_1": {
              "allowed_image_providers": [
                "123456738923",   // ops publisher
                "111122223333",   // vendor 1
                "444455556666",   // vendor 2
                "777788889999",   // exception (if not expired)
                "222233334444"    // exception (if not expired)
              ]
            }
          },
          
          "exception_message": "AMI not approved..."
        }
      }
    }
  }
}
```

**Key fields:**
- `state`: Controls enforcement
  - `audit_mode`: Log violations, don't block
  - `enabled`: Block non-compliant launches
- `@@operators_allowed_for_child_policies`: `["@@none"]` prevents override in child OUs
- `allowed_image_providers`: Array of approved AWS account IDs

#### 3. Service Control Policy Structure

**dist/scp-ami-guardrail.json:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyEC2LaunchWithNonApprovedAMIs",
      "Effect": "Deny",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet",
        "ec2:RequestSpotInstances",
        "ec2:RunScheduledInstances"
      ],
      "Resource": "arn:aws:ec2:*::image/*",
      "Condition": {
        "StringNotEquals": {
          "ec2:Owner": [
            "123456738923",   // Must match declarative policy
            "111122223333",
            "444455556666",
            "777788889999",
            "222233334444"
          ]
        }
      }
    },
    {
      "Sid": "DenyAMICreationAndSideload",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateImage",      // Create AMI from instance
        "ec2:CopyImage",        // Copy AMI from another region/account
        "ec2:RegisterImage",    // Register external image
        "ec2:ImportImage"       // Import VM/snapshot
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyPublicAMISharing",
      "Effect": "Deny",
      "Action": [
        "ec2:ModifyImageAttribute"
      ],
      "Resource": "arn:aws:ec2:*::image/*",
      "Condition": {
        "StringEquals": {
          "ec2:Add/group": "all"
        }
      }
    }
  ]
}
```

#### 4. Policy Generation Logic

**scripts/generate_policies.py algorithm:**

```python
def generate_allowlist():
    allowlist = set()
    
    # Step 1: Add ops publisher (always active)
    allowlist.add(config['ops_publisher_account']['account_id'])
    
    # Step 2: Add vendor publishers (always active)
    for vendor in config['vendor_publisher_accounts']:
        allowlist.add(vendor['account_id'])
    
    # Step 3: Filter and add active exceptions
    today = date.today()
    for exception in config['exception_accounts']:
        expires_on = date.fromisoformat(exception['expires_on'])
        
        if expires_on >= today:
            allowlist.add(exception['account_id'])
        else:
            log_warning(f"Expired: {exception['account_id']}")
    
    return sorted(list(allowlist))

def generate_policies(enforcement_mode):
    allowlist = generate_allowlist()
    
    # Generate declarative policy
    declarative = {
        "content": {
            "ec2": {
                "ec2_attributes": {
                    "allowed_images_settings": {
                        "state": enforcement_mode,
                        "image_criteria": {
                            "criteria_1": {
                                "allowed_image_providers": allowlist
                            }
                        }
                    }
                }
            }
        }
    }
    
    # Generate SCP (same allowlist)
    scp = {
        "Statement": [{
            "Condition": {
                "StringNotEquals": {
                    "ec2:Owner": allowlist  // MUST match declarative
                }
            }
        }]
    }
    
    # Verify consistency
    assert declarative_allowlist == scp_allowlist
    
    return declarative, scp
```

#### 5. Validation Pipeline

**CI validation steps:**

```yaml
validate:
  - Load config JSON
  - Check for expired exceptions
  - Generate policies
  - Compare allowlists between policies
  - Fail if mismatch or expired exceptions found
```

**Exit codes:**
- `0`: All validations passed
- `1`: Errors found (expired exceptions, invalid JSON, allowlist mismatch)

---

## Policy Enforcement Flow

### EC2 Launch Request Flow

```
┌────────────────────────────────────────────────────────────────────┐
│  Developer in Workload Account                                     │
│                                                                      │
│  $ aws ec2 run-instances \                                         │
│      --image-id ami-abc123 \                                       │
│      --instance-type t3.micro                                      │
└──────────────────────┬───────────────────────────────────────────┬─┘
                       │                                           │
                       ▼                                           ▼
           ┌───────────────────────┐                   ┌───────────────────────┐
           │  SCP Evaluation       │                   │ Declarative Policy    │
           │  (Layer 1)            │                   │ Evaluation (Layer 2)  │
           │                       │                   │                       │
           │  Check:               │                   │ Check:                │
           │  • ec2:Owner in       │                   │ • AMI owner in        │
           │    allowlist?         │                   │   allowed_image_      │
           │                       │                   │   providers?          │
           └───────┬───────────────┘                   └───────┬───────────────┘
                   │                                           │
                   │ Both checks must pass                     │
                   │                                           │
                   ▼                                           ▼
           ┌───────────────────────────────────────────────────────┐
           │             AMI Owner Validation                      │
           │                                                       │
           │  1. Extract AMI owner account from AMI metadata       │
           │  2. Compare against allowlist                         │
           │  3. Decision:                                         │
           │     • Owner in allowlist → ALLOW                      │
           │     • Owner NOT in allowlist → DENY                   │
           └───────────────────────────┬───────────────────────────┘
                                       │
                   ┌───────────────────┴───────────────────┐
                   │                                       │
                   ▼                                       ▼
        ┌────────────────────┐                 ┌────────────────────┐
        │  ALLOW             │                 │  DENY              │
        │                    │                 │                    │
        │  • Instance        │                 │  • Error message   │
        │    launches        │                 │  • CloudTrail log  │
        │  • CloudTrail log  │                 │  • User sees       │
        │                    │                 │    exception msg   │
        └────────────────────┘                 └────────────────────┘
```

### AMI Creation Attempt Flow

```
┌────────────────────────────────────────────────────────────────────┐
│  Developer in Workload Account                                     │
│                                                                      │
│  $ aws ec2 create-image \                                          │
│      --instance-id i-123456 \                                      │
│      --name "my-custom-ami"                                        │
└──────────────────────┬─────────────────────────────────────────────┘
                       │
                       ▼
           ┌───────────────────────┐
           │  SCP Evaluation       │
           │                       │
           │  Statement:           │
           │  "DenyAMICreationAnd  │
           │   Sideload"           │
           │                       │
           │  Effect: Deny         │
           │  Action:              │
           │   - ec2:CreateImage   │
           │   - ec2:CopyImage     │
           │   - ec2:RegisterImage │
           │   - ec2:ImportImage   │
           └───────┬───────────────┘
                   │
                   ▼
        ┌────────────────────┐
        │  DENY              │
        │                    │
        │  Error:            │
        │  AccessDenied      │
        │                    │
        │  "You are not      │
        │   authorized..."   │
        └────────────────────┘
```

### Public AMI Sharing Attempt Flow

```
┌────────────────────────────────────────────────────────────────────┐
│  Developer attempts to make AMI public                             │
│                                                                      │
│  $ aws ec2 modify-image-attribute \                                │
│      --image-id ami-owned-by-me \                                  │
│      --launch-permission "Add=[{Group=all}]"                       │
└──────────────────────┬─────────────────────────────────────────────┘
                       │
                       ▼
           ┌───────────────────────┐
           │  Dual Enforcement     │
           │                       │
           │  1. Declarative       │
           │     Policy:           │
           │     image_block_      │
           │     public_access =   │
           │     "block_new_       │
           │     sharing"          │
           │                       │
           │  2. SCP:              │
           │     Deny              │
           │     ModifyImage       │
           │     Attribute when    │
           │     Add/group=all     │
           └───────┬───────────────┘
                   │
                   ▼
        ┌────────────────────┐
        │  DENY              │
        │                    │
        │  Error:            │
        │  OperationNot      │
        │  Permitted or      │
        │  AccessDenied      │
        └────────────────────┘
```

---

## Exception Management

### Exception Lifecycle

```
┌────────────────────────────────────────────────────────────────────┐
│  1. REQUEST                                                        │
│     • Submit ticket with justification                             │
│     • Obtain required approvals                                    │
│     • Max duration: 90 days                                        │
└──────────────────────┬─────────────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────────────┐
│  2. IMPLEMENTATION                                                 │
│     • Update config/ami_publishers.json                            │
│     • Add exception with expires_on date                           │
│     • Generate policies (python generate_policies.py)              │
│     • CI validates: JSON format, expiry date, allowlist match      │
└──────────────────────┬─────────────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────────────┐
│  3. DEPLOYMENT                                                     │
│     • Merge to main branch                                         │
│     • Apply updated declarative policy at Org Root                 │
│     • Apply updated SCP at Org Root                                │
│     • Exception account can now launch its AMIs                    │
└──────────────────────┬─────────────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────────────┐
│  4. MONITORING                                                     │
│     • Daily CI check for expiring exceptions                       │
│     • Warning: 14 days before expiry                               │
│     • Error: On or after expiry date                               │
└──────────────────────┬─────────────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────────────┐
│  5. EXPIRY / RENEWAL                                               │
│     • Option A: Remove from config (auto-enforcement)              │
│     • Option B: Extend with new approval (update expires_on)       │
│     • Option C: Migrate to golden AMI (recommended)                │
└────────────────────────────────────────────────────────────────────┘
```

### Exception State Transitions

```
                     ┌──────────────────┐
                     │   REQUESTED      │
                     │  (Pending        │
                     │   Approval)      │
                     └────────┬─────────┘
                              │
                    approval obtained
                              │
                              ▼
                     ┌──────────────────┐
                     │   APPROVED       │
                     │  (Ready for      │
                     │   Config)        │
                     └────────┬─────────┘
                              │
                     config updated + merged
                              │
                              ▼
                     ┌──────────────────┐
                     │   ACTIVE         │
                     │  (In allowlist)  │
                     │  expires_on >=   │
                     │  today           │
                     └────────┬─────────┘
                              │
                  ┌───────────┼───────────┐
                  │           │           │
        expires_on < today    │      renewed (new expires_on)
                  │           │           │
                  ▼           │           ▼
         ┌──────────────┐    │    ┌──────────────────┐
         │  EXPIRED     │    │    │  EXTENDED        │
         │  (Must       │    │    │  (New expiry     │
         │   Remove)    │    │    │   date)          │
         └──────┬───────┘    │    └────────┬─────────┘
                │            │             │
                │            │             └────────┐
                │            │                      │
                │     migrated to golden AMI        │
                │            │                      │
                ▼            ▼                      ▼
         ┌────────────────────────────────────────────┐
         │             REMOVED                        │
         │  (Deleted from config)                     │
         └────────────────────────────────────────────┘
```

---

## Deployment Architecture

### Phase 1: Audit Mode

**Purpose:** Validate policy impact without blocking

```
┌─────────────────────────────────────────────────────────────────────┐
│  AWS Organization Root                                              │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Declarative Policy                                         │    │
│  │  allowed_images_settings.state = "audit_mode"              │    │
│  │                                                             │    │
│  │  Effect: Non-compliant launches SUCCEED                     │    │
│  │          but logged as violations                           │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  SCP (Same allowlist)                                       │    │
│  │                                                             │    │
│  │  Effect: Non-compliant launches BLOCKED                     │    │
│  │          (SCP enforces even in audit mode)                  │    │
│  └────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘

Monitoring:
• CloudTrail: Filter eventName=RunInstances + errorCode
• Organizations Console: Compliance status dashboard
• Review violations for 2-4 weeks
```

### Phase 2: Enforcement Mode

**Purpose:** Full blocking of non-compliant launches

```
┌─────────────────────────────────────────────────────────────────────┐
│  AWS Organization Root                                              │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Declarative Policy                                         │    │
│  │  allowed_images_settings.state = "enabled"                 │    │
│  │                                                             │    │
│  │  Effect: Non-compliant launches BLOCKED                     │    │
│  │          with user-friendly error message                   │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  SCP (Same allowlist)                                       │    │
│  │                                                             │    │
│  │  Effect: Defense-in-depth blocking                          │    │
│  │          (Prevents policy bypass)                           │    │
│  └────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘

Result:
• Full enforcement at both policy layers
• AMI creation operations blocked
• Public AMI sharing prevented
• Only approved AMI publishers allowed
```

### GitOps Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│  Developer Workstation                                              │
│                                                                       │
│  1. Clone repo                                                       │
│  2. Create feature branch                                            │
│  3. Edit config/ami_publishers.json                                 │
│  4. Run: python generate_policies.py                                │
│  5. Run: python validate_policies.py                                │
│  6. Commit + push                                                    │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  GitLab CI Pipeline                                                 │
│                                                                       │
│  ┌────────────┐    ┌──────────────┐    ┌──────────────────┐       │
│  │ Validate   │ -> │ Generate     │ -> │ Verify           │       │
│  │ Config     │    │ Policies     │    │ Consistency      │       │
│  └────────────┘    └──────────────┘    └──────────────────┘       │
│                                                                       │
│  • Check JSON format                                                │
│  • Check for expired exceptions                                     │
│  • Verify allowlist match between policies                          │
│  • Generate artifacts in dist/                                      │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
                   CI passes
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Merge Request Review                                               │
│                                                                       │
│  • Cloud Platform Team approval                                     │
│  • Security team approval (for exceptions)                          │
│  • Review CI output (active allowlist summary)                      │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
                   Approved + merged
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Manual Deployment                                                  │
│                                                                       │
│  1. Download artifacts: dist/declarative-policy-ec2.json            │
│  2. Download artifacts: dist/scp-ami-guardrail.json                 │
│  3. Apply to AWS Organizations Root via console                     │
│     (or use AWS CLI)                                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Developers launching instances with vulnerable AMIs | Allowlist enforcement prevents non-approved AMIs |
| Developers creating custom AMIs to bypass controls | SCP denies all AMI creation operations in workloads |
| Lateral movement via AMI sharing | SCP denies public AMI sharing |
| Policy bypass via child OU override | `@@operators_allowed_for_child_policies: ["@@none"]` |
| Stale exceptions remaining active | Daily CI checks fail on expired exceptions |
| Manual policy edits causing drift | GitOps enforces config as code |
| Inconsistent allowlists between policies | CI validation checks for allowlist match |

### Compliance Mappings

| Control | Implementation |
|---------|----------------|
| **CIS AWS Benchmark 5.1** - Ensure no hardcoded credentials in AMIs | Golden AMI program enforces secure build process |
| **SOC 2 CC6.6** - Use of approved vendors | Vendor publishers tracked in config |
| **NIST 800-53 CM-2** - Baseline Configuration | Golden AMIs provide approved baselines |
| **NIST 800-53 CM-7** - Least Functionality | Golden AMIs hardened per standards |
| **ISO 27001 A.12.5.1** - Installation of software on operational systems | Only approved AMIs can be used |

---

## Appendix

### Policy Size Limits

- **Declarative Policy:** 2,048 characters max per policy document
- **SCP:** 5,120 characters max per policy document
- **Allowlist size:** Practically limited by JSON size, recommend < 50 accounts

### Performance Considerations

- **Policy evaluation:** < 100ms overhead per API call
- **CI pipeline:** ~30 seconds per validation run
- **Daily exception check:** ~10 seconds

### Related AWS Documentation

- [AWS Organizations Declarative Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html)
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [EC2 Image Block Public Access](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/sharingamis-intro.html#block-public-access-to-amis)

---

**END OF ARCHITECTURE DOCUMENT**
