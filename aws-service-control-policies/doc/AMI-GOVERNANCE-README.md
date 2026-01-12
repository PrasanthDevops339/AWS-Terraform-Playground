# 🛡️ AMI Governance Policy Documentation

> **Version:** 2026-01-11  
> **Policy Type:** Dual-Layer Enforcement (SCP + Declarative Policy)  
> **Managed By:** Cloud Security Team  

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Account Reference Matrix](#account-reference-matrix)
- [Principal Access Matrix](#principal-access-matrix)
- [Policy Components](#policy-components)
- [SCP Statement Details](#scp-statement-details)
- [Declarative Policy Details](#declarative-policy-details)
- [Enforcement Flow](#enforcement-flow)
- [Exception Process](#exception-process)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

This AMI Governance solution provides **enterprise-grade control** over Amazon Machine Image (AMI) usage across your AWS Organization. It implements a **dual-layer enforcement model** that combines:

1. **EC2 Declarative Policy** - Native AWS service-level enforcement
2. **Service Control Policy (SCP)** - IAM boundary with principal-based restrictions

### Key Features

| Feature | Description |
|---------|-------------|
| ✅ **Approved Publishers Only** | Only designated AWS accounts can provide AMIs |
| ✅ **Principal-Based Restrictions** | Exception AMIs restricted to specific IAM roles |
| ✅ **Sideloading Prevention** | Blocks unauthorized AMI creation/import |
| ✅ **Public Sharing Block** | Prevents AMIs from being made public |
| ✅ **Audit Mode Support** | Test policies before full enforcement |
| ✅ **Exception Expiry Ready** | Built-in support for time-bound exceptions |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS ORGANIZATION                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     POLICY ENFORCEMENT LAYERS                        │    │
│  │  ┌─────────────────────────┐   ┌─────────────────────────────────┐  │    │
│  │  │   DECLARATIVE POLICY    │   │    SERVICE CONTROL POLICY       │  │    │
│  │  │   (EC2 Service Level)   │   │    (IAM Boundary)               │  │    │
│  │  │                         │   │                                  │  │    │
│  │  │  • Allowed AMI Sources  │   │  • Block Non-Approved AMIs      │  │    │
│  │  │  • Block Public Sharing │   │  • Principal-Based Restrictions │  │    │
│  │  │  • Audit Mode Support   │   │  • Sideloading Prevention       │  │    │
│  │  │                         │   │  • Public Sharing Block         │  │    │
│  │  └─────────────────────────┘   └─────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      AMI PUBLISHER ACCOUNTS                          │    │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │    │
│  │  │ Operations  │ │  InfoBlox   │ │   General   │ │    TFE      │    │    │
│  │  │123456738923 │ │111122223333 │ │222233334444 │ │444455556666 │    │    │
│  │  │   OPEN      │ │   OPEN      │ │   OPEN      │ │ RESTRICTED  │    │    │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │    │
│  │                                                   ┌─────────────┐    │    │
│  │                                                   │  Migration  │    │    │
│  │                                                   │777788889999 │    │    │
│  │                                                   │ RESTRICTED  │    │    │
│  │                                                   └─────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Account Reference Matrix

### Approved AMI Publisher Accounts

| Account ID | Account Name | ARN Pattern | Access Level | Description |
|:----------:|:-------------|:------------|:------------:|:------------|
| `123456738923` | **Operations AMI Publisher** | `arn:aws:iam::123456738923:*` | 🟢 **OPEN** | Central operations team AMI publishing account |
| `111122223333` | **InfoBlox Vendor** | `arn:aws:iam::111122223333:*` | 🟢 **OPEN** | InfoBlox vendor AMI account |
| `222233334444` | **General Vendor** | `arn:aws:iam::222233334444:*` | 🟢 **OPEN** | General vendor AMI account |
| `444455556666` | **Terraform Enterprise** | `arn:aws:iam::444455556666:*` | 🟡 **RESTRICTED** | TFE exception - specific roles only |
| `777788889999` | **Migration Exception** | `arn:aws:iam::777788889999:*` | 🟡 **RESTRICTED** | Migration exception - specific roles only |

### Access Level Legend

| Symbol | Level | Description |
|:------:|:------|:------------|
| 🟢 | **OPEN** | Anyone in the organization can use AMIs from this account |
| 🟡 | **RESTRICTED** | Only specific IAM principals can use AMIs from this account |
| 🔴 | **BLOCKED** | All other AMI sources are blocked |

---

## 👥 Principal Access Matrix

### Who Can Use Which AMIs?

| AMI Source Account | Account ID | Any Role | Admin* Role | Developer* Role | TFE* Role | Migration* Role |
|:-------------------|:----------:|:--------:|:-----------:|:---------------:|:---------:|:---------------:|
| **Operations** | `123456738923` | ✅ | ✅ | ✅ | ✅ | ✅ |
| **InfoBlox Vendor** | `111122223333` | ✅ | ✅ | ✅ | ✅ | ✅ |
| **General Vendor** | `222233334444` | ✅ | ✅ | ✅ | ✅ | ✅ |
| **TFE Exception** | `444455556666` | ❌ | ✅ | ✅ | ✅ | ❌ |
| **Migration Exception** | `777788889999` | ❌ | ✅ | ✅ | ❌ | ✅ |
| **All Other Sources** | `*` | ❌ | ❌ | ❌ | ❌ | ❌ |

### Detailed Principal ARN Permissions

#### TFE Exception Account (`444455556666`)

| Principal ARN Pattern | Access |
|:----------------------|:------:|
| `arn:aws:iam::444455556666:role/Admin*` | ✅ Allowed |
| `arn:aws:iam::444455556666:role/Developer*` | ✅ Allowed |
| `arn:aws:iam::444455556666:role/TerraformEnterprise*` | ✅ Allowed |
| `arn:aws:iam::*:role/*` (any other role) | ❌ Denied |
| `arn:aws:iam::*:user/*` (any user) | ❌ Denied |

#### Migration Exception Account (`777788889999`)

| Principal ARN Pattern | Access |
|:----------------------|:------:|
| `arn:aws:iam::777788889999:role/Admin*` | ✅ Allowed |
| `arn:aws:iam::777788889999:role/Developer*` | ✅ Allowed |
| `arn:aws:iam::777788889999:role/MigrationRole*` | ✅ Allowed |
| `arn:aws:iam::*:role/*` (any other role) | ❌ Denied |
| `arn:aws:iam::*:user/*` (any user) | ❌ Denied |

---

## 📜 Policy Components

### Policy Files

| File Name | Type | Version | Purpose |
|:----------|:-----|:--------|:--------|
| `scp-ami-guardrail-2026-01-11.json` | SERVICE_CONTROL_POLICY | 2026-01-11 | IAM boundary with principal restrictions |
| `declarative-policy-ec2-2026-01-11.json` | DECLARATIVE_POLICY_EC2 | 2026-01-11 | EC2 service-level enforcement |

---

## 📋 SCP Statement Details

### Statement Matrix

| # | Statement ID | Effect | Actions | Condition | Target |
|:-:|:-------------|:-------|:--------|:----------|:-------|
| 1 | `DenyEC2LaunchWithNonApprovedAMIs` | DENY | RunInstances, CreateFleet, RequestSpotInstances, RunScheduledInstances | `ec2:Owner` NOT in approved list | All AMIs not in approved list |
| 2 | `DenyExceptionAMIUsageByUnauthorizedPrincipals` | DENY | RunInstances, CreateFleet, RequestSpotInstances, RunScheduledInstances | `ec2:Owner` = `444455556666` AND `aws:PrincipalArn` NOT LIKE approved | TFE AMIs by unauthorized principals |
| 3 | `DenyMigrationExceptionAMIUsageByUnauthorizedPrincipals` | DENY | RunInstances, CreateFleet, RequestSpotInstances, RunScheduledInstances | `ec2:Owner` = `777788889999` AND `aws:PrincipalArn` NOT LIKE approved | Migration AMIs by unauthorized principals |
| 4 | `DenyAMICreationAndSideload` | DENY | CreateImage, CopyImage, RegisterImage, ImportImage | None | All principals |
| 5 | `DenyPublicAMISharing` | DENY | ModifyImageAttribute | `ec2:Add/group` = `all` | Public sharing attempts |

### Statement 1: Block Non-Approved AMI Sources

```
┌─────────────────────────────────────────────────────────────────┐
│  DenyEC2LaunchWithNonApprovedAMIs                               │
├─────────────────────────────────────────────────────────────────┤
│  EFFECT: DENY                                                    │
│                                                                  │
│  ACTIONS:                                                        │
│    • ec2:RunInstances                                           │
│    • ec2:CreateFleet                                            │
│    • ec2:RequestSpotInstances                                   │
│    • ec2:RunScheduledInstances                                  │
│                                                                  │
│  CONDITION:                                                      │
│    ec2:Owner NOT IN [                                           │
│      123456738923,  ← Operations                                │
│      111122223333,  ← InfoBlox                                  │
│      222233334444,  ← General Vendor                            │
│      444455556666,  ← TFE Exception                             │
│      777788889999   ← Migration Exception                       │
│    ]                                                             │
│                                                                  │
│  RESULT: Any AMI from unlisted accounts = BLOCKED               │
└─────────────────────────────────────────────────────────────────┘
```

### Statement 2: TFE Exception Principal Restriction

```
┌─────────────────────────────────────────────────────────────────┐
│  DenyExceptionAMIUsageByUnauthorizedPrincipals                  │
├─────────────────────────────────────────────────────────────────┤
│  EFFECT: DENY                                                    │
│                                                                  │
│  CONDITION (ALL must match):                                     │
│    ┌─────────────────────────────────────────────────────────┐  │
│    │  ec2:Owner = 444455556666 (TFE Account)                 │  │
│    └─────────────────────────────────────────────────────────┘  │
│                        AND                                       │
│    ┌─────────────────────────────────────────────────────────┐  │
│    │  aws:PrincipalArn NOT LIKE:                             │  │
│    │    • arn:aws:iam::444455556666:role/Admin*              │  │
│    │    • arn:aws:iam::444455556666:role/Developer*          │  │
│    │    • arn:aws:iam::444455556666:role/TerraformEnterprise*│  │
│    └─────────────────────────────────────────────────────────┘  │
│                                                                  │
│  RESULT: TFE AMIs can ONLY be used by Admin/Developer/TFE roles │
└─────────────────────────────────────────────────────────────────┘
```

### Statement 3: Migration Exception Principal Restriction

```
┌─────────────────────────────────────────────────────────────────┐
│  DenyMigrationExceptionAMIUsageByUnauthorizedPrincipals         │
├─────────────────────────────────────────────────────────────────┤
│  EFFECT: DENY                                                    │
│                                                                  │
│  CONDITION (ALL must match):                                     │
│    ┌─────────────────────────────────────────────────────────┐  │
│    │  ec2:Owner = 777788889999 (Migration Account)           │  │
│    └─────────────────────────────────────────────────────────┘  │
│                        AND                                       │
│    ┌─────────────────────────────────────────────────────────┐  │
│    │  aws:PrincipalArn NOT LIKE:                             │  │
│    │    • arn:aws:iam::777788889999:role/Admin*              │  │
│    │    • arn:aws:iam::777788889999:role/Developer*          │  │
│    │    • arn:aws:iam::777788889999:role/MigrationRole*      │  │
│    └─────────────────────────────────────────────────────────┘  │
│                                                                  │
│  RESULT: Migration AMIs can ONLY be used by Admin/Dev/Migration │
└─────────────────────────────────────────────────────────────────┘
```

### Statement 4 & 5: Sideloading & Public Sharing Prevention

```
┌─────────────────────────────────────────────────────────────────┐
│  DenyAMICreationAndSideload          DenyPublicAMISharing       │
├─────────────────────────────────────────────────────────────────┤
│  BLOCKED ACTIONS:                    BLOCKED WHEN:              │
│    • ec2:CreateImage                   ec2:Add/group = "all"    │
│    • ec2:CopyImage                                              │
│    • ec2:RegisterImage               Prevents making AMIs       │
│    • ec2:ImportImage                 publicly accessible        │
│                                                                  │
│  Prevents bypassing governance                                   │
│  by creating local AMIs                                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Declarative Policy Details

### EC2 Declarative Policy Settings

| Setting | Current Value | Options | Description |
|:--------|:--------------|:--------|:------------|
| `image_block_public_access.state` | `block_new_sharing` | `block_new_sharing`, `unblocked` | Blocks public AMI sharing |
| `allowed_images_settings.state` | `audit_mode` | `enabled`, `audit_mode`, `disabled` | Controls AMI source enforcement |

### Enforcement State Progression

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  DISABLED   │ ──► │ AUDIT_MODE  │ ──► │   ENABLED   │
│             │     │             │     │             │
│  No logging │     │ Log only    │     │ Full block  │
│  No blocking│     │ No blocking │     │ + logging   │
└─────────────┘     └─────────────┘     └─────────────┘
                          ▲
                          │
                    CURRENT STATE
                    (Recommended for
                     initial rollout)
```

---

## 🔄 Enforcement Flow

### Decision Tree

```
                         ┌─────────────────────────┐
                         │  EC2 Launch Request     │
                         │  (RunInstances, etc.)   │
                         └───────────┬─────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │  Is AMI Owner in Approved List? │
                    │  [123456738923, 111122223333,   │
                    │   222233334444, 444455556666,   │
                    │   777788889999]                 │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────NO──────┴──────YES───────┐
                    │                                  │
                    ▼                                  ▼
            ┌───────────────┐              ┌─────────────────────┐
            │   ❌ DENIED    │              │ Is Owner Exception? │
            │   Statement 1  │              │ (444455556666 OR    │
            │                │              │  777788889999)      │
            └───────────────┘              └──────────┬──────────┘
                                                      │
                                      ┌────NO─────────┴──────YES────┐
                                      │                             │
                                      ▼                             ▼
                              ┌───────────────┐        ┌───────────────────────┐
                              │  ✅ ALLOWED    │        │ Is Principal in       │
                              │  Open Access   │        │ Allowed Role List?    │
                              │                │        │ (Admin*/Developer*/   │
                              └───────────────┘        │  TFE*/Migration*)     │
                                                       └───────────┬───────────┘
                                                                   │
                                                   ┌────NO─────────┴──────YES────┐
                                                   │                             │
                                                   ▼                             ▼
                                           ┌───────────────┐            ┌───────────────┐
                                           │   ❌ DENIED    │            │  ✅ ALLOWED    │
                                           │ Statement 2/3  │            │  Principal OK  │
                                           │ Unauthorized   │            │                │
                                           └───────────────┘            └───────────────┘
```

---

## 📝 Exception Process

### Request Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     EXCEPTION REQUEST PROCESS                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Submit Jira Ticket                                          │
│     https://jira.company.com/browse/CLOUD                       │
│                                                                  │
│  2. Required Information:                                        │
│     ┌─────────────────────────────────────────────────────────┐ │
│     │  • Business justification                                │ │
│     │  • Account ID requiring exception                        │ │
│     │  • AMI source account/ID                                 │ │
│     │  • Duration needed (max 90 days)                         │ │
│     │  • Security team approval                                │ │
│     │  • Principal ARNs that need access                       │ │
│     └─────────────────────────────────────────────────────────┘ │
│                                                                  │
│  3. Security Review (2-3 business days)                         │
│                                                                  │
│  4. If Approved:                                                 │
│     • Add account to exception_accounts with expiry date        │
│     • Add principal ARNs to SCP statement                       │
│     • Deploy via Terraform pipeline                             │
│                                                                  │
│  5. Automatic Expiry:                                            │
│     • Exception expiry feature removes access after date        │
│     • (Feature currently disabled, can be enabled)              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Troubleshooting

### Common Error Messages

| Error | Cause | Resolution |
|:------|:------|:-----------|
| "User: arn:aws:iam::xxx:role/MyRole is not authorized to perform: ec2:RunInstances on resource: arn:aws:ec2:*::image/ami-xxx" | AMI not from approved source | Use AMI from approved publisher account |
| "Access denied for TFE AMI" | Principal not in allowed list | Ensure using Admin/Developer/TFE role |
| "Access denied for Migration AMI" | Principal not in allowed list | Ensure using Admin/Developer/Migration role |
| "Cannot create AMI" | Sideloading prevention | Contact Operations team for official AMI |

### CloudTrail Event Lookup

```bash
# Find AMI-related denials
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --start-time $(date -d '1 hour ago' --iso-8601=seconds) \
  --query 'Events[?contains(CloudTrailEvent, `AccessDenied`)]'
```

---

## 📚 Related Documentation

- [AWS Organizations SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [EC2 Declarative Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html)
- [AMI Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html)

---

## 📞 Contact

| Team | Contact | Purpose |
|:-----|:--------|:--------|
| Cloud Security | cloudsec@company.com | Policy questions, exceptions |
| Operations | ops@company.com | AMI publishing, golden images |
| Platform | platform@company.com | Terraform, infrastructure |

---

> **Last Updated:** 2026-01-11  
> **Maintained By:** Cloud Security Team  
> **Review Cycle:** Quarterly
