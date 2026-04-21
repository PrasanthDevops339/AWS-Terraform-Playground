# 🛡️ Prasa AMI Governance Policy Documentation

> **Version:** 2026-01-18  
> **Policy Type:** Dual-Layer Enforcement (SCP + Declarative Policy)  
> **Managed By:** Prasa Cloud Security Team  

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prasa Operations Accounts](#prasa-operations-accounts)
- [Approved AMI Catalog](#approved-ami-catalog)
- [Policy Components](#policy-components)
- [SCP Statement Details](#scp-statement-details)
- [Declarative Policy Details](#declarative-policy-details)
- [Enforcement Flow](#enforcement-flow)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

This AMI Governance solution provides **enterprise-grade control** over Amazon Machine Image (AMI) usage across the Prasa AWS Organization. It implements a **dual-layer enforcement model** that combines:

1. **EC2 Declarative Policy** - Native AWS service-level enforcement
2. **Service Control Policy (SCP)** - IAM boundary enforcement

### Key Features

| Feature | Description |
|---------|-------------|
| ✅ **Prasa Operations Only** | Only AMIs from Prasa Operations accounts are permitted |
| ✅ **Sideloading Prevention** | Blocks unauthorized AMI creation/import |
| ✅ **Public Sharing Block** | Prevents AMIs from being made public |
| ✅ **Audit Mode Support** | Test policies before full enforcement |
| ✅ **Standardized Naming** | Consistent `prasa-*` naming convention |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PRASA AWS ORGANIZATION                                │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     POLICY ENFORCEMENT LAYERS                        │    │
│  │  ┌─────────────────────────┐   ┌─────────────────────────────────┐  │    │
│  │  │   DECLARATIVE POLICY    │   │    SERVICE CONTROL POLICY       │  │    │
│  │  │   (EC2 Service Level)   │   │    (IAM Boundary)               │  │    │
│  │  │                         │   │                                  │  │    │
│  │  │  • Allowed AMI Sources  │   │  • Block Non-Approved AMIs      │  │    │
│  │  │  • Block Public Sharing │   │  • Sideloading Prevention       │  │    │
│  │  │  • Audit Mode Support   │   │  • Public Sharing Block         │  │    │
│  │  └─────────────────────────┘   └─────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                   PRASA OPERATIONS AMI PUBLISHERS                    │    │
│  │                                                                       │    │
│  │  ┌─────────────────────────────┐   ┌─────────────────────────────┐   │    │
│  │  │  prasains-operations-dev    │   │  prasains-operations-prd    │   │    │
│  │  │        565656565656         │   │        666363636363         │   │    │
│  │  │         (DEV)               │   │         (PRD)               │   │    │
│  │  │       us-east-2             │   │       us-east-2             │   │    │
│  │  └─────────────────────────────┘   └─────────────────────────────┘   │    │
│  │                                                                       │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │    │
│  │  │                    APPROVED AMI TYPES                           │ │    │
│  │  │  • prasa-rhel8-*    • prasa-win16-*    • prasa-al2023-*        │ │    │
│  │  │  • prasa-rhel9-*    • prasa-win19-*    • prasa-al2-2024-*      │ │    │
│  │  │  • prasa-mlal2-*    • prasa-win22-*    • prasa-opsdir-mlal2-*  │ │    │
│  │  └─────────────────────────────────────────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🏢 Prasa Operations Accounts

### AMI Publisher Accounts

| Account ID | Account Alias | Region | Environment | Description |
|:----------:|:--------------|:------:|:-----------:|:------------|
| `565656565656` | **prasains-operations-dev-use2** | us-east-2 | 🟡 DEV | Prasa Operations DEV - AMI publishing account |
| `666363636363` | **prasains-operations-prd-use2** | us-east-2 | 🟢 PRD | Prasa Operations PRD - AMI publishing account |

### Account ARN Reference

| Account | ARN |
|:--------|:----|
| Prasa Operations DEV | `arn:aws:iam::565656565656:root` |
| Prasa Operations PRD | `arn:aws:iam::666363636363:root` |

---

## 📦 Approved AMI Catalog

### 1️⃣ Marketplace Customized (MarkLogic)

AMIs based on AWS Marketplace MarkLogic, customized for Prasa environment.

| AMI Name Pattern | AMI Alias | Base Image | OS |
|:-----------------|:----------|:-----------|:---|
| `prasa-opsdir-mlal2-*` | `prasa-OPSDIR-MLAL2-CF` | MarkLogic | Amazon Linux 2 |
| `prasa-mlal2-*` | `prasa-MLAL2-CF` | MarkLogic | Amazon Linux 2 |

### 2️⃣ Prasa Customized (AWS Base Images)

AWS base images customized by Prasa Operations team.

#### Linux AMIs

| AMI Name Pattern | AMI Alias | Operating System | Status |
|:-----------------|:----------|:-----------------|:------:|
| `prasa-rhel8-*` | `prasa-rhel8-cf` | Red Hat Enterprise Linux 8 | ✅ Active |
| `prasa-rhel9-*` | `prasa-rhel9-cf` | Red Hat Enterprise Linux 9 | ✅ Active |
| `prasa-al2023-*` | `prasa-al2023-cf` | Amazon Linux 2023 | ✅ Active |
| `prasa-al2-2024-*` | `prasa-al2-2024-cf` | Amazon Linux 2 (2024) | ✅ Active |

#### Windows AMIs

| AMI Name Pattern | AMI Alias | Operating System | Status |
|:-----------------|:----------|:-----------------|:------:|
| `prasa-win16-*` | `prasa-win16-cf` | Windows Server 2016 | ⚠️ Legacy |
| `prasa-win19-*` | `prasa-win19-cf` | Windows Server 2019 | ✅ Active |
| `prasa-win22-*` | `prasa-win22-cf` | Windows Server 2022 | ✅ Active |

### AMI Naming Convention

```
prasa-{os}-{version}-{date}-{build}

Examples:
  prasa-rhel9-20260115-001
  prasa-win22-20260110-002
  prasa-al2023-20260118-001
  prasa-mlal2-20260105-001
```

---

## 📊 Complete AMI Access Matrix

| Source | Account ID | Account Alias | Who Can Use | Status |
|:-------|:----------:|:--------------|:-----------:|:------:|
| **Prasa Ops DEV** | `565656565656` | prasains-operations-dev-use2 | ✅ Anyone in Org | 🟢 Approved |
| **Prasa Ops PRD** | `666363636363` | prasains-operations-prd-use2 | ✅ Anyone in Org | 🟢 Approved |
| **AWS Marketplace** | `*` | Various | ❌ Blocked | 🔴 Denied |
| **Community AMIs** | `*` | Various | ❌ Blocked | 🔴 Denied |
| **Third Party** | `*` | Various | ❌ Blocked | 🔴 Denied |
| **Self-Created** | `*` | Various | ❌ Blocked | 🔴 Denied |

---

## 📜 Policy Components

### Policy Files

| File Name | Type | Version | Purpose |
|:----------|:-----|:--------|:--------|
| `scp-ami-guardrail-2026-01-18.json` | SERVICE_CONTROL_POLICY | 2026-01-18 | IAM boundary enforcement |
| `declarative-policy-ec2-2026-01-18.json` | DECLARATIVE_POLICY_EC2 | 2026-01-18 | EC2 service-level enforcement |

---

## 📋 SCP Statement Details

### Statement Matrix

| # | Statement ID | Effect | Actions | Condition | Impact |
|:-:|:-------------|:-------|:--------|:----------|:-------|
| 1 | `DenyEC2LaunchWithNonApprovedAMIs` | DENY | RunInstances, CreateFleet, RequestSpotInstances, RunScheduledInstances | `ec2:Owner` NOT in [565656565656, 666363636363] | Blocks non-Prasa AMIs |
| 2 | `DenyAMICreationAndSideload` | DENY | CreateImage, CopyImage, RegisterImage, ImportImage | None | Prevents sideloading |
| 3 | `DenyPublicAMISharing` | DENY | ModifyImageAttribute | `ec2:Add/group` = `all` | Blocks public sharing |

### Statement 1: Block Non-Prasa AMI Sources

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
│      565656565656  ← prasains-operations-dev-use2               │
│      666363636363  ← prasains-operations-prd-use2               │
│    ]                                                             │
│                                                                  │
│  RESULT: Any AMI from non-Prasa Operations accounts = BLOCKED   │
└─────────────────────────────────────────────────────────────────┘
```

### Statement 2: Prevent AMI Sideloading

```
┌─────────────────────────────────────────────────────────────────┐
│  DenyAMICreationAndSideload                                     │
├─────────────────────────────────────────────────────────────────┤
│  EFFECT: DENY                                                    │
│                                                                  │
│  BLOCKED ACTIONS:                                                │
│    • ec2:CreateImage      ← Cannot create AMI from instance     │
│    • ec2:CopyImage        ← Cannot copy AMIs                    │
│    • ec2:RegisterImage    ← Cannot register external images     │
│    • ec2:ImportImage      ← Cannot import VM images             │
│                                                                  │
│  EXCEPTION:                                                      │
│    Prasa Operations accounts excluded via OU attachment         │
│                                                                  │
│  RESULT: Only Prasa Operations can create/publish AMIs          │
└─────────────────────────────────────────────────────────────────┘
```

### Statement 3: Prevent Public AMI Sharing

```
┌─────────────────────────────────────────────────────────────────┐
│  DenyPublicAMISharing                                           │
├─────────────────────────────────────────────────────────────────┤
│  EFFECT: DENY                                                    │
│                                                                  │
│  ACTION: ec2:ModifyImageAttribute                               │
│                                                                  │
│  CONDITION:                                                      │
│    ec2:Add/group = "all"  ← Indicates public sharing attempt    │
│                                                                  │
│  RESULT: No AMIs can be made publicly accessible                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Declarative Policy Details

### EC2 Declarative Policy Settings

| Setting | Current Value | Options | Description |
|:--------|:--------------|:--------|:------------|
| `image_block_public_access.state` | `block_new_sharing` | `block_new_sharing`, `unblocked` | Blocks public AMI sharing |
| `allowed_images_settings.state` | `audit_mode` | `enabled`, `audit_mode`, `disabled` | Controls AMI source enforcement |

### Allowed Image Providers

```
┌─────────────────────────────────────────────────────────────────┐
│  allowed_image_providers                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  565656565656  │  prasains-operations-dev-use2  │  DEV      ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  666363636363  │  prasains-operations-prd-use2  │  PRD      ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

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
                    │  Is AMI Owner a Prasa Ops       │
                    │  Account?                       │
                    │  [565656565656, 666363636363]   │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────NO──────┴──────YES───────┐
                    │                                  │
                    ▼                                  ▼
            ┌───────────────┐              ┌───────────────────────┐
            │   ❌ DENIED    │              │  Is AMI Name Pattern  │
            │               │              │  Valid?               │
            │  SCP blocks   │              │  prasa-{os}-*         │
            │  non-Prasa    │              └───────────┬───────────┘
            │  AMI sources  │                          │
            └───────────────┘              ┌───YES─────┴──────NO───┐
                                           │                       │
                                           ▼                       ▼
                                   ┌───────────────┐       ┌───────────────┐
                                   │  ✅ ALLOWED    │       │  ⚠️ WARNING   │
                                   │               │       │               │
                                   │  Valid Prasa  │       │  Non-standard │
                                   │  AMI          │       │  naming       │
                                   └───────────────┘       └───────────────┘
```

---

## 🔧 Troubleshooting

### Common Error Messages

| Error | Cause | Resolution |
|:------|:------|:-----------|
| "Access Denied: ec2:RunInstances on image/ami-xxx" | AMI not from Prasa Operations account | Use AMI from `565656565656` or `666363636363` |
| "Cannot create image" | Sideloading prevention active | Contact Prasa Operations for official AMI |
| "Cannot modify image attribute" | Public sharing blocked | AMIs cannot be made public |

### Verify AMI Owner

```bash
# Check AMI owner account
aws ec2 describe-images --image-ids ami-xxxxxxxxx \
  --query 'Images[0].OwnerId' --output text

# Expected output: 565656565656 or 666363636363
```

### List Available Prasa AMIs

```bash
# List all Prasa AMIs from Operations DEV
aws ec2 describe-images \
  --owners 565656565656 \
  --query 'Images[*].[Name,ImageId,CreationDate]' \
  --output table

# List all Prasa AMIs from Operations PRD
aws ec2 describe-images \
  --owners 666363636363 \
  --query 'Images[*].[Name,ImageId,CreationDate]' \
  --output table
```

### Find AMIs by Pattern

```bash
# Find RHEL 9 AMIs
aws ec2 describe-images \
  --owners 565656565656 666363636363 \
  --filters "Name=name,Values=prasa-rhel9-*" \
  --query 'Images[*].[Name,ImageId,CreationDate]' \
  --output table

# Find Windows Server 2022 AMIs
aws ec2 describe-images \
  --owners 565656565656 666363636363 \
  --filters "Name=name,Values=prasa-win22-*" \
  --query 'Images[*].[Name,ImageId,CreationDate]' \
  --output table
```

---

## 📚 Quick Reference Card

### Prasa Operations Accounts

| Environment | Account ID | Alias |
|:-----------:|:----------:|:------|
| DEV | `565656565656` | prasains-operations-dev-use2 |
| PRD | `666363636363` | prasains-operations-prd-use2 |

### Approved AMI Patterns

| Category | Patterns |
|:---------|:---------|
| **Linux** | `prasa-rhel8-*`, `prasa-rhel9-*`, `prasa-al2023-*`, `prasa-al2-2024-*` |
| **Windows** | `prasa-win16-*`, `prasa-win19-*`, `prasa-win22-*` |
| **MarkLogic** | `prasa-mlal2-*`, `prasa-opsdir-mlal2-*` |

### AMI Aliases (CloudFormation)

| Alias | Description |
|:------|:------------|
| `prasa-rhel8-cf` | RHEL 8 |
| `prasa-rhel9-cf` | RHEL 9 |
| `prasa-win16-cf` | Windows 2016 |
| `prasa-win19-cf` | Windows 2019 |
| `prasa-win22-cf` | Windows 2022 |
| `prasa-al2023-cf` | Amazon Linux 2023 |
| `prasa-al2-2024-cf` | Amazon Linux 2 (2024) |
| `prasa-MLAL2-CF` | MarkLogic |
| `prasa-OPSDIR-MLAL2-CF` | MarkLogic OpsDir |

---

## 📞 Contact

| Team | Contact | Purpose |
|:-----|:--------|:--------|
| Prasa Operations | ops@prasa.com | AMI requests, golden images |
| Cloud Security | cloudsec@prasa.com | Policy questions, exceptions |
| Platform Team | platform@prasa.com | Terraform, infrastructure |

---

> **Last Updated:** 2026-01-18  
> **Maintained By:** Prasa Cloud Security Team  
> **Review Cycle:** Quarterly

