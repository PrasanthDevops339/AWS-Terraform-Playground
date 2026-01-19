# EC2 Declarative Policies — AMI Governance Field Guide# EC2 Declarative Policies (AWS Organizations) — Field Guide for Platform Engineers# EC2 Declarative Policies (AWS Organizations) — Field Guide for Platform Engineers



> **Purpose:** Focused guide on using **EC2 Declarative Policies** for AMI governance in AWS Organizations, covering **Allowed Images Settings** and **Image Block Public Access**.

>

> **Updated:** 2026-01-18 | **Organization:** Prasa> **Purpose:** This is a **mid-level** "how it actually works in practice" guide to **EC2 declarative policies** in AWS Organizations, with special focus on **AMI restriction (Allowed AMIs / Allowed Images Settings)** and the **modes** each attribute supports.> Purpose: This is a **mid-level** “how it actually works in practice” guide to **EC2 declarative policies** in AWS Organizations, with special focus on **AMI restriction (Allowed AMIs / Allowed Images Settings)** and the **modes** each attribute supports.



--->



## 📋 Table of Contents> **Updated:** 2026-01-18 | **Organization:** Prasa---



- [Prasa Quick Reference](#prasa-quick-reference)

- [What Are Declarative Policies?](#1-what-are-declarative-policies)

- [Policy Syntax & Operators](#2-policy-syntax--operators)---## 1) What declarative policies are

- [Image Block Public Access](#3-image-block-public-access)

- [Allowed Images Settings](#4-allowed-images-settings-the-ami-restriction-engine)

- [Custom Exception Messages](#5-custom-exception-messages)

- [Production Rollout Guide](#6-production-rollout-guide)## Prasa Operations Quick Reference**Declarative policies** are an AWS Organizations policy type that lets you centrally **declare and enforce EC2 account-attribute configuration** across accounts/OUs/root. Unlike SCPs (authorization-time allow/deny), declarative policies are **enforced by the service control plane**. That means:

- [Complete Prasa Policy Example](#7-complete-prasa-declarative-policy)

- [CLI Commands & Troubleshooting](#8-cli-commands--troubleshooting)



---### Approved AMI Publisher Accounts- The service maintains the “desired state” configuration you declare.



## Prasa Quick Reference- **Noncompliant actions fail** at the service level.



### Approved AMI Publisher Accounts| Account ID | Account Alias | Environment | Region |- Account admins generally **can’t override** an attribute that’s enforced by declarative policy.



| Account ID | Account Alias | Environment | Region ||:----------:|:--------------|:-----------:|:------:|

|:----------:|:--------------|:-----------:|:------:|

| `565656565656` | prasains-operations-dev-use2 | DEV | us-east-2 || `565656565656` | prasains-operations-dev-use2 | DEV | us-east-2 |**Why you’d use it:** governance that’s closer to “configuration management” than “permissions management”, especially for settings that can’t be reliably controlled with IAM conditions alone.

| `666363636363` | prasains-operations-prd-use2 | PRD | us-east-2 |

| `666363636363` | prasains-operations-prd-use2 | PRD | us-east-2 |

### Approved AMI Patterns

---

| Category | AMI Name Patterns | AMI Aliases (CF) |

|:---------|:------------------|:-----------------|### Approved AMI Patterns

| **MarkLogic** | `prasa-opsdir-mlal2-*`, `prasa-mlal2-*` | `prasa-OPSDIR-MLAL2-CF`, `prasa-MLAL2-CF` |

| **RHEL** | `prasa-rhel8-*`, `prasa-rhel9-*` | `prasa-rhel8-cf`, `prasa-rhel9-cf` |## 2) How to use EC2 declarative policies (practical workflow)

| **Windows** | `prasa-win16-*`, `prasa-win19-*`, `prasa-win22-*` | `prasa-win16-cf`, `prasa-win19-cf`, `prasa-win22-cf` |

| **Amazon Linux** | `prasa-al2023-*`, `prasa-al2-2024-*` | `prasa-al2023-cf`, `prasa-al2-2024-cf` || Category | AMI Name Patterns | AMI Aliases |



---|:---------|:------------------|:------------|### 2.1 High-level rollout (recommended)



## 1) What Are Declarative Policies?| **MarkLogic** | `prasa-opsdir-mlal2-*`, `prasa-mlal2-*` | `prasa-OPSDIR-MLAL2-CF`, `prasa-MLAL2-CF` |1. **Generate an account status report** (inventory current config across the org)



**Declarative policies** are an AWS Organizations policy type that lets you centrally **declare and enforce EC2 account-attribute configuration** across accounts/OUs/root.| **RHEL** | `prasa-rhel8-*`, `prasa-rhel9-*` | `prasa-rhel8-cf`, `prasa-rhel9-cf` |2. Start with a **pilot OU/account**



### How They Differ from SCPs| **Windows** | `prasa-win16-*`, `prasa-win19-*`, `prasa-win22-*` | `prasa-win16-cf`, `prasa-win19-cf`, `prasa-win22-cf` |3. Validate the **effective policy** on a target account



| Aspect | SCPs | Declarative Policies || **Amazon Linux** | `prasa-al2023-*`, `prasa-al2-2024-*` | `prasa-al2023-cf`, `prasa-al2-2024-cf` |4. Expand to broader OUs / root

|:-------|:-----|:--------------------|

| **Enforcement** | Authorization-time (IAM) | Service control plane |

| **Mechanism** | Allow/Deny permissions | Configuration management |

| **Override** | Can be bypassed with right permissions | Account admins **cannot override** |---### 2.2 Where you attach

| **Scope** | All AWS services | Specific service attributes |

You can attach policies to:

### Key Characteristics

## 1) What declarative policies are- Organization **root**

- ✅ The service maintains the "desired state" configuration you declare

- ✅ **Noncompliant actions fail** at the service level- an **OU**

- ✅ Account admins **cannot override** enforced attributes

- ✅ Closer to "configuration management" than "permissions management"**Declarative policies** are an AWS Organizations policy type that lets you centrally **declare and enforce EC2 account-attribute configuration** across accounts/OUs/root. Unlike SCPs (authorization-time allow/deny), declarative policies are **enforced by the service control plane**. That means:- an **account**



### Why Use Declarative Policies for AMI Governance?



| Benefit | Description |- The service maintains the "desired state" configuration you declare.### 2.3 “Effective policy” (your safety rail)

|:--------|:------------|

| **Native Enforcement** | EC2 service itself enforces the rules |- **Noncompliant actions fail** at the service level.In AWS Organizations, the **effective policy** for an account is the combination of inherited policies + directly attached policy (for the given policy type). You should treat “DescribeEffectivePolicy” as a required validation step in CI/CD.

| **No IAM Workarounds** | Can't be bypassed with IAM permissions |

| **Centralized Control** | Single policy controls entire org/OU |- Account admins generally **can't override** an attribute that's enforced by declarative policy.

| **Audit Mode** | Test before enforcement |

| **Custom Messages** | Helpful error messages for developers |---



---**Why you'd use it:** governance that's closer to "configuration management" than "permissions management", especially for settings that can't be reliably controlled with IAM conditions alone.



## 2) Policy Syntax & Operators## 3) Syntax essentials (and the inheritance operators)



### Basic Structure---



```jsonA declarative policy is **JSON** and starts with the fixed top-level key:

{

  "ec2_attributes": {## 2) How to use EC2 declarative policies (practical workflow)

    "image_block_public_access": { },

    "allowed_images_settings": { }```json

  }

}### 2.1 High-level rollout (recommended){

```

1. **Generate an account status report** (inventory current config across the org)  "ec2_attributes": {

### Value-Setting Operators

2. Start with a **pilot OU/account**    "...": {}

| Operator | Purpose | Example |

|:---------|:--------|:--------|3. Validate the **effective policy** on a target account  }

| `@@assign` | Set/overwrite a value | `"state": { "@@assign": "enabled" }` |

| `@@append` | Add to inherited list | `"@@append": ["565656565656"]` |4. Expand to broader OUs / root}

| `@@remove` | Remove from inherited list | `"@@remove": ["old-account-id"]` |

```

### Inheritance Control

### 2.2 Where you attach

Use `@@operators_allowed_for_child_policies` to restrict what child OUs/accounts can do:

You can attach policies to:### 3.1 Value-setting operators

| Value | Effect |

|:------|:-------|- Organization **root**Declarative policies use the same value-setting operators as other Organizations management policy types:

| `["@@none"]` | Children **cannot** change this setting (locked) |

| `["@@append"]` | Children can only add to lists, not overwrite |- an **OU**

| `["@@assign", "@@append"]` | Children can set or add values |

- an **account**- `@@assign` → set/overwrite a value

**Example: Lock down for Prasa (recommended)**

```json- `@@append` → add values to a list inherited from parents

{

  "ec2_attributes": {### 2.3 "Effective policy" (your safety rail)- `@@remove` → remove specific values from an inherited list

    "@@operators_allowed_for_child_policies": ["@@none"],

    "allowed_images_settings": {In AWS Organizations, the **effective policy** for an account is the combination of inherited policies + directly attached policy (for the given policy type). You should treat "DescribeEffectivePolicy" as a required validation step in CI/CD.

      "@@operators_allowed_for_child_policies": ["@@none"],

      "state": { "@@assign": "enabled" }Example:

    }

  }---

}

``````json



---## 3) Syntax essentials (and the inheritance operators){



## 3) Image Block Public Access  "ec2_attributes": {



### What It ControlsA declarative policy is **JSON** and starts with the fixed top-level key:    "allowed_images_settings": {

Prevents AMIs from being **publicly shared** (public launch permissions).

      "image_criteria": {

### Modes

```json        "criteria_1": {

| State | Description | Use Case |

|:------|:------------|:---------|{          "allowed_image_providers": {

| `unblocked` | No restrictions. Accounts can publicly share AMIs. | ❌ Not recommended |

| `block_new_sharing` | Prevents **new** public sharing. Already-public AMIs remain public. | ✅ **Prasa standard** |  "ec2_attributes": {            "@@append": ["amazon", "111122223333"]



### Visual Flow    "...": {}          }



```  }        }

┌─────────────────────────────────────────────────────────────────┐

│                  IMAGE BLOCK PUBLIC ACCESS                       │}      }

├─────────────────────────────────────────────────────────────────┤

│                                                                  │```    }

│   state = "unblocked"           state = "block_new_sharing"     │

│   ┌─────────────────┐           ┌─────────────────────────────┐ │  }

│   │  AMI can be     │           │  ❌ New public sharing      │ │

│   │  shared publicly│           │     BLOCKED                 │ │### 3.1 Value-setting operators}

│   │  ⚠️ RISK        │           │  ✅ Already-public AMIs     │ │

│   └─────────────────┘           │     remain public           │ │Declarative policies use the same value-setting operators as other Organizations management policy types:```

│                                 └─────────────────────────────┘ │

│                                                                  │

└─────────────────────────────────────────────────────────────────┘

```- `@@assign` → set/overwrite a value### 3.2 Controlling what child OUs/accounts can do



### Policy Example (Prasa Standard)- `@@append` → add values to a list inherited from parentsUse `@@operators_allowed_for_child_policies` to restrict what descendants can do.



```json- `@@remove` → remove specific values from an inherited list

{

  "ec2_attributes": {- `["@@none"]` → children can’t change that subtree

    "image_block_public_access": {

      "@@operators_allowed_for_child_policies": ["@@none"],Example (Prasa Operations accounts):- Or allow only some ops, like `["@@append"]` if you want children to add to a list but not overwrite it

      "state": { "@@assign": "block_new_sharing" }

    }

  }

}```jsonExample (lock it down):

```

{

### API Operations Blocked

When `block_new_sharing` is active:  "ec2_attributes": {```json

- `ModifyImageAttribute` with `LaunchPermission.Add.Group = all` → **DENIED**

- `CreateStoreImageTask` with public settings → **DENIED**    "allowed_images_settings": {{



---      "image_criteria": {  "ec2_attributes": {



## 4) Allowed Images Settings (The AMI Restriction Engine)        "criteria_1": {    "allowed_images_settings": {



### What It Controls          "allowed_image_providers": {      "@@operators_allowed_for_child_policies": ["@@none"],

Controls the **discovery and use** of AMIs in EC2 by defining a central allowlist (criteria).

            "@@assign": ["565656565656", "666363636363"]      "state": { "@@assign": "enabled" }

### The 3 Operational Modes

          }    }

```

┌─────────────┐     ┌─────────────┐     ┌─────────────┐        }  }

│  DISABLED   │ ──► │ AUDIT_MODE  │ ──► │   ENABLED   │

│             │     │             │     │             │      }}

│ No logging  │     │ Log only    │     │ Full block  │

│ No blocking │     │ No blocking │     │ + logging   │    }```

│ No criteria │     │ Find issues │     │ Enforced    │

└─────────────┘     └─────────────┘     └─────────────┘  }

       ▲                   ▲                   ▲

       │                   │                   │}---

   Rollback           Phase 1              Phase 2

   or not ready       (Testing)          (Production)```

```

## 4) The EC2 attributes you can control (and their modes)

### Mode Details

### 3.2 Controlling what child OUs/accounts can do

#### Mode 1: `disabled`

Use `@@operators_allowed_for_child_policies` to restrict what descendants can do.AWS Organizations currently supports these EC2-related attributes in declarative policies:

| Aspect | Description |

|:-------|:------------|

| **Behavior** | No enforcement, no compliance evaluation |

| **When to use** | During rollback, or if not ready to constrain AMIs |- `["@@none"]` → children can't change that subtree- **VPC Block Public Access**

| **Impact** | All AMIs can be used |

- Or allow only some ops, like `["@@append"]` if you want children to add to a list but not overwrite it- **Serial Console Access**

```json

{- **Image Block Public Access**

  "ec2_attributes": {

    "allowed_images_settings": {Example (lock it down for Prasa):- **Allowed Images Settings** (Allowed AMIs)

      "state": { "@@assign": "disabled" }

    }- **Instance Metadata Defaults** (IMDS defaults)

  }

}```json- **Snapshot Block Public Access**

```

{

#### Mode 2: `audit_mode` ⭐ Start Here

  "ec2_attributes": {This section explains **each attribute’s modes/states**, what they mean, and gives a practical example.

| Aspect | Description |

|:-------|:------------|    "allowed_images_settings": {

| **Behavior** | **Does NOT block** usage, but identifies non-compliant AMIs |

| **When to use** | First phase of rollout to find issues before enforcement |      "@@operators_allowed_for_child_policies": ["@@none"],---

| **Impact** | Workloads continue running; violations are logged |

      "state": { "@@assign": "enabled" },

**What you'll observe:**

- `DescribeImages` includes `imageAllowed` indicator      "image_criteria": {# 4A) VPC Block Public Access (VPC BPA)

- CloudTrail logs show which AMIs would be blocked

- No disruption to existing workloads        "criteria_1": {



```json          "allowed_image_providers": {### What it controls

{

  "ec2_attributes": {            "@@assign": ["565656565656", "666363636363"]Whether VPC/subnet resources can reach the internet through internet gateways (IGWs), via an account-level VPC Block Public Access mode.

    "allowed_images_settings": {

      "state": { "@@assign": "audit_mode" },          }

      "image_criteria": {

        "criteria_1": {        }### Modes (`internet_gateway_block.mode`)

          "allowed_image_providers": { 

            "@@assign": ["565656565656", "666363636363"]       }- **`off`**  

          }

        }    }  VPC BPA is not enabled.

      }

    }  }

  }

}}- **`block_ingress`**  

```

```  Blocks inbound internet traffic to VPCs (except excluded VPCs/subnets). NAT gateways and egress-only IGWs still allow outbound connections because they’re outbound-initiated.

#### Mode 3: `enabled` (Full Enforcement)



| Aspect | Description |

|:-------|:------------|---- **`block_bidirectional`**  

| **Behavior** | **Blocks** non-compliant AMIs from being discovered/used |

| **When to use** | After audit_mode proves teams are compliant |  Blocks both inbound and outbound via IGWs/egress-only IGWs (except excluded VPCs/subnets).

| **Impact** | Only allowed AMIs can be used for EC2 launches |

## 4) The EC2 attributes you can control (and their modes)

```json

{### Exclusions (`internet_gateway_block.exclusions_allowed`)

  "ec2_attributes": {

    "allowed_images_settings": {AWS Organizations currently supports these EC2-related attributes in declarative policies:- **`enabled`** → accounts may create exclusions

      "@@operators_allowed_for_child_policies": ["@@none"],

      "state": { "@@assign": "enabled" },- **`disabled`** → accounts may not create exclusions

      "image_criteria": {

        "criteria_1": {- **VPC Block Public Access**

          "allowed_image_providers": { 

            "@@assign": ["565656565656", "666363636363"] - **Serial Console Access**> Important: the policy can allow/disallow exclusions, but **does not create exclusions**. Exclusions are created inside the owning account.

          },

          "image_names": { - **Image Block Public Access**

            "@@assign": [

              "prasa-rhel8-*",- **Allowed Images Settings** (Allowed AMIs)#### Example: block ingress, allow exclusions

              "prasa-rhel9-*",

              "prasa-win16-*",- **Instance Metadata Defaults** (IMDS defaults)```json

              "prasa-win19-*",

              "prasa-win22-*",- **Snapshot Block Public Access**{

              "prasa-al2023-*",

              "prasa-al2-2024-*",  "ec2_attributes": {

              "prasa-mlal2-*",

              "prasa-opsdir-mlal2-*"This section explains **each attribute's modes/states**, what they mean, and gives a practical example.    "vpc_block_public_access": {

            ] 

          }      "internet_gateway_block": {

        }

      }---        "mode": { "@@assign": "block_ingress" },

    }

  }        "exclusions_allowed": { "@@assign": "enabled" }

}

```# 4A) VPC Block Public Access (VPC BPA)      }



### Criteria Fields (The Allowlist Language)    }



You can have up to **10 criteria** (`criteria_1` through `criteria_10`). An AMI must match **at least one** criteria to be allowed.### What it controls  }



| Field | Description | Example |Whether VPC/subnet resources can reach the internet through internet gateways (IGWs), via an account-level VPC Block Public Access mode.}

|:------|:------------|:--------|

| `allowed_image_providers` | Account IDs or aliases that can provide AMIs | `["565656565656", "666363636363"]` |```

| `image_names` | AMI name patterns (wildcards `*` and `?` supported) | `["prasa-rhel*", "prasa-win*"]` |

| `marketplace_product_codes` | Specific AWS Marketplace product codes | `["abc123xyz"]` |### Modes (`internet_gateway_block.mode`)

| `creation_date_condition.maximum_days_since_created` | Max age in days (freshness window) | `90` |

| `deprecation_time_condition.maximum_days_since_deprecated` | Days since deprecation | `30` |- **`off`**  ---



### Special Provider Aliases  VPC BPA is not enabled.



| Alias | Description |# 4B) Serial Console Access

|:------|:------------|

| `amazon` | AWS-provided AMIs |- **`block_ingress`**  

| `aws_marketplace` | All AWS Marketplace AMIs |

| `aws_backup_vault` | AWS Backup vault AMIs |  Blocks inbound internet traffic to VPCs (except excluded VPCs/subnets). NAT gateways and egress-only IGWs still allow outbound connections because they're outbound-initiated.### What it controls

| `self` | AMIs owned by the account itself |

Whether the EC2 Serial Console is accessible.

### Criteria Logic (AND vs OR)

- **`block_bidirectional`**  

```

┌─────────────────────────────────────────────────────────────────┐  Blocks both inbound and outbound via IGWs/egress-only IGWs (except excluded VPCs/subnets).### Modes (`serial_console_access.status`)

│                    CRITERIA EVALUATION                          │

├─────────────────────────────────────────────────────────────────┤- **`enabled`** → serial console allowed

│                                                                  │

│  WITHIN a single criteria: ALL conditions must match (AND)      │### Exclusions (`internet_gateway_block.exclusions_allowed`)- **`disabled`** → serial console blocked

│  ┌─────────────────────────────────────────────────────────────┐│

│  │  criteria_1:                                                ││- **`enabled`** → accounts may create exclusions

│  │    allowed_image_providers = ["565656565656"]    ← AND      ││

│  │    image_names = ["prasa-rhel*"]                 ← AND      ││- **`disabled`** → accounts may not create exclusions#### Example: disable serial console

│  │    maximum_days_since_created = 90               ← AND      ││

│  └─────────────────────────────────────────────────────────────┘│```json

│                                                                  │

│  BETWEEN criteria: ANY criteria can match (OR)                  │> Important: the policy can allow/disallow exclusions, but **does not create exclusions**. Exclusions are created inside the owning account.{

│  ┌─────────────────────────────────────────────────────────────┐│

│  │  criteria_1 (Prasa AMIs)           ← OR                     ││  "ec2_attributes": {

│  │  criteria_2 (Amazon AMIs)          ← OR                     ││

│  │  criteria_3 (Marketplace AMIs)     ← OR                     ││#### Example: block ingress, allow exclusions    "serial_console_access": {

│  └─────────────────────────────────────────────────────────────┘│

│                                                                  │```json      "status": { "@@assign": "disabled" }

└─────────────────────────────────────────────────────────────────┘

```{    }



### Example: Multiple Criteria  "ec2_attributes": {  }



```json    "vpc_block_public_access": {}

{

  "ec2_attributes": {      "internet_gateway_block": {```

    "allowed_images_settings": {

      "state": { "@@assign": "enabled" },        "mode": { "@@assign": "block_ingress" },

      "image_criteria": {

        "criteria_1": {        "exclusions_allowed": { "@@assign": "enabled" }---

          "_comment": "Prasa Operations AMIs",

          "allowed_image_providers": {       }

            "@@assign": ["565656565656", "666363636363"] 

          },    }# 4C) Image Block Public Access (AMI public sharing guardrail)

          "image_names": { 

            "@@assign": ["prasa-*"]   }

          }

        },}### What it controls

        "criteria_2": {

          "_comment": "Amazon-provided AMIs (optional)",```Whether AMIs can be publicly shared (public launch permissions).

          "allowed_image_providers": { 

            "@@assign": ["amazon"] 

          }

        }---### Modes (`image_block_public_access.state`)

      }

    }- **`unblocked`**  

  }

}# 4B) Serial Console Access  No restrictions. Accounts can publicly share new AMIs.

```



---

### What it controls- **`block_new_sharing`**  

## 5) Custom Exception Messages

Whether the EC2 Serial Console is accessible.  Prevents **new** public sharing. AMIs that are *already* public remain public.

Define a helpful error message when noncompliant actions fail.



### Prasa Custom Message

### Modes (`serial_console_access.status`)#### Example: stop new public AMI sharing

```json

{- **`enabled`** → serial console allowed```json

  "ec2_attributes": {

    "exception_message": {- **`disabled`** → serial console blocked{

      "@@assign": "AMI not approved for use in Prasa organization. Only prasa-* AMIs from Operations accounts (prasains-operations-dev-use2: 565656565656, prasains-operations-prd-use2: 666363636363) are permitted. Approved patterns: prasa-rhel8-*, prasa-rhel9-*, prasa-win16-*, prasa-win19-*, prasa-win22-*, prasa-al2023-*, prasa-al2-2024-*, prasa-mlal2-*, prasa-opsdir-mlal2-*. To request an exception, submit a Jira ticket."

    }  "ec2_attributes": {

  }

}#### Example: disable serial console    "image_block_public_access": {

```

```json      "state": { "@@assign": "block_new_sharing" }

### Best Practices

{    }

| Do | Don't |

|:---|:------|  "ec2_attributes": {  }

| ✅ Include approved AMI patterns | ❌ Include secrets or PII |

| ✅ Provide exception request process | ❌ Make it too long |    "serial_console_access": {}

| ✅ List approved account aliases | ❌ Use technical jargon only |

      "status": { "@@assign": "disabled" }```

---

    }

## 6) Production Rollout Guide

  }---

### Phase 0: Preparation

}

- [x] Establish golden AMI publishing pipeline (Packer, EC2 Image Builder)

- [x] Adopt naming convention: `prasa-{os}-{version}-{date}-{build}````# 4D) Allowed Images Settings (Allowed AMIs) — the AMI restriction engine

- [x] Confirm Operations accounts: `565656565656`, `666363636363`



### Phase 1: Audit Mode (Weeks 1-4)

---### What it controls

**Goal:** Identify non-compliant AMI usage without breaking anything.

Controls the **discovery and use** of AMIs in EC2 by defining a central allowlist (criteria).

```json

{# 4C) Image Block Public Access (AMI public sharing guardrail)

  "ec2_attributes": {

    "allowed_images_settings": {### The 3 operational modes (`allowed_images_settings.state`)

      "state": { "@@assign": "audit_mode" },

      "image_criteria": {### What it controls

        "criteria_1": {

          "allowed_image_providers": { Whether AMIs can be publicly shared (public launch permissions).#### Mode 1 — `disabled`

            "@@assign": ["565656565656", "666363636363"] 

          }**Meaning:** No enforcement; no compliance evaluation.  

        }

      }### Modes (`image_block_public_access.state`)**When you use it:** during rollout rollback, or if you’re not ready to constrain AMIs.

    },

    "image_block_public_access": {- **`unblocked`**  

      "state": { "@@assign": "block_new_sharing" }

    }  No restrictions. Accounts can publicly share new AMIs.**Example:**

  }

}```json

```

- **`block_new_sharing`**  {

**Actions:**

1. Deploy to pilot OU/account  Prevents **new** public sharing. AMIs that are *already* public remain public.  "ec2_attributes": {

2. Monitor CloudTrail for `imageAllowed: false` events

3. Work with teams to migrate to approved AMIs    "allowed_images_settings": {

4. Validate with `describe-effective-policy`

#### Example: stop new public AMI sharing (Prasa standard)      "state": { "@@assign": "disabled" }

### Phase 2: Enabled (Full Enforcement)

```json    }

**Goal:** Block non-compliant AMIs.

{  }

```json

{  "ec2_attributes": {}

  "ec2_attributes": {

    "@@operators_allowed_for_child_policies": ["@@none"],    "image_block_public_access": {```

    

    "exception_message": {      "state": { "@@assign": "block_new_sharing" }

      "@@assign": "AMI not approved. Only prasa-* AMIs from Prasa Operations accounts permitted. Submit Jira for exceptions."

    },    }#### Mode 2 — `audit_mode`

    

    "allowed_images_settings": {  }**Meaning:** **Do not block** usage, but **identify** whether AMIs would be allowed by your criteria.  

      "@@operators_allowed_for_child_policies": ["@@none"],

      "state": { "@@assign": "enabled" },}**When you use it:** the first phase of rollout to find breakage before enforcement.

      "image_criteria": {

        "criteria_1": {```

          "allowed_image_providers": { 

            "@@assign": ["565656565656", "666363636363"] **What you’ll observe:**  

          },

          "image_names": { ---- APIs like `DescribeImages` can include an `imageAllowed` style signal in results when in audit mode (service-side behavior depends on API; the core idea is “tagging” vs “blocking”).

            "@@assign": [

              "prasa-rhel8-*", "prasa-rhel9-*",- Workloads still run, but you can detect “would fail later” cases.

              "prasa-win16-*", "prasa-win19-*", "prasa-win22-*",

              "prasa-al2023-*", "prasa-al2-2024-*",# 4D) Allowed Images Settings (Allowed AMIs) — the AMI restriction engine

              "prasa-mlal2-*", "prasa-opsdir-mlal2-*"

            ] **Example:**

          }

        }### What it controls```json

      }

    },Controls the **discovery and use** of AMIs in EC2 by defining a central allowlist (criteria).{

    

    "image_block_public_access": {  "ec2_attributes": {

      "@@operators_allowed_for_child_policies": ["@@none"],

      "state": { "@@assign": "block_new_sharing" }### The 3 operational modes (`allowed_images_settings.state`)    "allowed_images_settings": {

    }

  }      "state": { "@@assign": "audit_mode" },

}

```#### Mode 1 — `disabled`      "image_criteria": {



### Phase 3: Add Age Restriction (Optional)**Meaning:** No enforcement; no compliance evaluation.          "criteria_1": {



Add freshness requirement after patch cadence is reliable:**When you use it:** during rollout rollback, or if you're not ready to constrain AMIs.          "allowed_image_providers": { "@@assign": ["amazon", "111122223333"] },



```json          "image_names": { "@@assign": ["xyzzy-golden-*"] }

"creation_date_condition": {

  "maximum_days_since_created": { "@@assign": 90 }**Example:**        }

}

``````json      }



### Rollout Checklist{    }



| Phase | Task | Status |  "ec2_attributes": {  }

|:------|:-----|:------:|

| 0 | Confirm Operations accounts | ⬜ |    "allowed_images_settings": {}

| 0 | Document AMI naming convention | ⬜ |

| 1 | Deploy audit_mode to pilot OU | ⬜ |      "state": { "@@assign": "disabled" }```

| 1 | Monitor CloudTrail (2-4 weeks) | ⬜ |

| 1 | Remediate non-compliant teams | ⬜ |    }

| 2 | Enable enforcement | ⬜ |

| 2 | Lock with `@@operators_allowed_for_child_policies` | ⬜ |  }#### Mode 3 — `enabled`

| 2 | Enable image_block_public_access | ⬜ |

| 3 | Add age restriction (optional) | ⬜ |}**Meaning:** **Enforced**. Only images that match your criteria are allowed/discoverable/usable (per Allowed AMIs behavior).  



---```**When you use it:** after audit mode proves teams are compliant.



## 7) Complete Prasa Declarative Policy



### Full Production-Ready Policy#### Mode 2 — `audit_mode`**Example:**



```json**Meaning:** **Do not block** usage, but **identify** whether AMIs would be allowed by your criteria.  ```json

{

  "ec2_attributes": {**When you use it:** the first phase of rollout to find breakage before enforcement.{

    "@@operators_allowed_for_child_policies": ["@@none"],

      "ec2_attributes": {

    "exception_message": {

      "@@assign": "AMI not approved for use in Prasa organization. Only prasa-* AMIs from Operations accounts (prasains-operations-dev-use2: 565656565656, prasains-operations-prd-use2: 666363636363) are permitted. Approved patterns: prasa-rhel8-*, prasa-rhel9-*, prasa-win16-*, prasa-win19-*, prasa-win22-*, prasa-al2023-*, prasa-al2-2024-*, prasa-mlal2-*, prasa-opsdir-mlal2-*. To request an exception, submit a Jira ticket."**What you'll observe:**      "allowed_images_settings": {

    },

    - APIs like `DescribeImages` can include an `imageAllowed` style signal in results when in audit mode (service-side behavior depends on API; the core idea is "tagging" vs "blocking").      "state": { "@@assign": "enabled" },

    "image_block_public_access": {

      "@@operators_allowed_for_child_policies": ["@@none"],- Workloads still run, but you can detect "would fail later" cases.      "image_criteria": {

      "state": { "@@assign": "block_new_sharing" }

    },        "criteria_1": {

    

    "allowed_images_settings": {**Example (Prasa Operations - audit mode):**          "allowed_image_providers": { "@@assign": ["111122223333"] },

      "@@operators_allowed_for_child_policies": ["@@none"],

      "state": { "@@assign": "audit_mode" },```json          "image_names": { "@@assign": ["xyzzy-golden-*"] },

      "image_criteria": {

        "criteria_1": {{          "creation_date_condition": {

          "allowed_image_providers": {

            "@@assign": ["565656565656", "666363636363"]  "ec2_attributes": {            "maximum_days_since_created": { "@@assign": 90 }

          },

          "image_names": {    "allowed_images_settings": {          }

            "@@assign": [

              "prasa-rhel8-*",      "state": { "@@assign": "audit_mode" },        }

              "prasa-rhel9-*",

              "prasa-win16-*",      "image_criteria": {      }

              "prasa-win19-*",

              "prasa-win22-*",        "criteria_1": {    }

              "prasa-al2023-*",

              "prasa-al2-2024-*",          "allowed_image_providers": {   }

              "prasa-mlal2-*",

              "prasa-opsdir-mlal2-*"            "@@assign": ["565656565656", "666363636363"] }

            ]

          }          },```

        }

      }          "image_names": { 

    }

  }            "@@assign": [### Criteria fields you can use (the allowlist “language”)

}

```              "prasa-rhel8-*",



---              "prasa-rhel9-*",Within each `criteria_N` (up to 10):



## 8) CLI Commands & Troubleshooting              "prasa-win16-*",- `allowed_image_providers`  



### Validate Effective Policy              "prasa-win19-*",  Allowed owners: 12-digit account IDs or aliases like `amazon`, `aws_marketplace`, `aws_backup_vault`.



```bash              "prasa-win22-*",- `image_names`  

# Check what policy is effective for an account

aws organizations describe-effective-policy \              "prasa-al2023-*",  Supports wildcards `*` and `?`.

  --policy-type DECLARATIVE_POLICY_EC2 \

  --target-id <account-id>              "prasa-al2-2024-*",- `marketplace_product_codes`  

```

              "prasa-mlal2-*",  Allow specific Marketplace AMIs.

### List Prasa AMIs

              "prasa-opsdir-mlal2-*"- `creation_date_condition.maximum_days_since_created`  

```bash

# List all AMIs from Prasa Operations DEV            ]   “Freshness” window.

aws ec2 describe-images \

  --owners 565656565656 \          }- `deprecation_time_condition.maximum_days_since_deprecated`  

  --query 'Images[*].[Name,ImageId,CreationDate]' \

  --output table        }  Time window after deprecation.



# List all AMIs from Prasa Operations PRD      }

aws ec2 describe-images \

  --owners 666363636363 \    }### Practical mid-level guidance: how to choose criteria

  --query 'Images[*].[Name,ImageId,CreationDate]' \

  --output table  }- Start with **provider allowlist** (your golden AMI publishing account + `amazon` if needed).



# Find specific pattern (e.g., RHEL 9)}- Add **name patterns** once you have a stable convention.

aws ec2 describe-images \

  --owners 565656565656 666363636363 \```- Add **age window** (like 60/90 days) after patch cadence is reliable.

  --filters "Name=name,Values=prasa-rhel9-*" \

  --query 'Images[*].[Name,ImageId,CreationDate]' \- Avoid making criteria too clever early—“audit_mode first” saves careers.

  --output table

```#### Mode 3 — `enabled`



### Verify AMI Owner**Meaning:** **Enforced**. Only images that match your criteria are allowed/discoverable/usable (per Allowed AMIs behavior).  ---



```bash**When you use it:** after audit mode proves teams are compliant.

# Check who owns an AMI

aws ec2 describe-images --image-ids ami-xxxxxxxxx \# 4E) Instance Metadata Defaults (IMDS defaults)

  --query 'Images[0].OwnerId' --output text

**Example (Prasa Operations - enforced with age limit):**

# Expected: 565656565656 or 666363636363

``````json### What it controls



### Common Errors{Sets **defaults** for IMDS behavior for **new instance launches** (not a “hard enforcement” of every IMDS aspect, but it’s still a powerful baseline).



| Error | Cause | Resolution |  "ec2_attributes": {

|:------|:------|:-----------|

| "Image is not allowed" | AMI not from approved account | Use AMI from `565656565656` or `666363636363` |    "allowed_images_settings": {### Fields and modes

| "Image name does not match" | AMI name doesn't match pattern | Use AMI with `prasa-*` naming |

| "Cannot modify image attribute" | Image block public access active | AMIs cannot be made public |      "state": { "@@assign": "enabled" },



### CloudTrail Event Names      "image_criteria": {#### `http_tokens`



| Event | Description |        "criteria_1": {- **`no_preference`** → other defaults apply (AMI defaults, etc.)

|:------|:------------|

| `DescribeImages` | Check `imageAllowed` field in audit mode |          "allowed_image_providers": { - **`required`** → IMDSv2 required; IMDSv1 not allowed

| `RunInstances` | Will fail if AMI not allowed (enabled mode) |

| `ModifyImageAttribute` | Will fail if trying to make public |            "@@assign": ["565656565656", "666363636363"] - **`optional`** → IMDSv1 + IMDSv2 allowed



---          },



## Quick Reference Card          "image_names": { #### `http_endpoint`



### Prasa Operations Accounts            "@@assign": [- **`no_preference`**



| Env | Account ID | Alias |              "prasa-rhel8-*",- **`enabled`** → IMDS endpoint accessible

|:---:|:----------:|:------|

| DEV | `565656565656` | prasains-operations-dev-use2 |              "prasa-rhel9-*",- **`disabled`** → IMDS endpoint not accessible

| PRD | `666363636363` | prasains-operations-prd-use2 |

              "prasa-win16-*",

### Allowed Images Settings States

              "prasa-win19-*",#### `instance_metadata_tags`

| State | Blocks? | Logs? | Use Case |

|:------|:-------:|:-----:|:---------|              "prasa-win22-*",- **`no_preference`**

| `disabled` | ❌ | ❌ | Rollback/not ready |

| `audit_mode` | ❌ | ✅ | Testing (Phase 1) |              "prasa-al2023-*",- **`enabled`** → tags accessible via IMDS

| `enabled` | ✅ | ✅ | Production (Phase 2) |

              "prasa-al2-2024-*",- **`disabled`** → tags not accessible via IMDS

### Image Block Public Access States

              "prasa-mlal2-*",

| State | Effect |

|:------|:-------|              "prasa-opsdir-mlal2-*"#### `http_put_response_hop_limit`

| `unblocked` | ❌ Not recommended |

| `block_new_sharing` | ✅ Prasa standard |            ] - Integer **-1 to 64**  



---          },  - `-1` means “no preference”



## AWS Documentation Links          "creation_date_condition": {  - If `http_tokens` is `required`, a hop limit of **>= 2** is typically recommended in real-world setups (containers, proxies, etc.).



- [Declarative policies overview](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html)            "maximum_days_since_created": { "@@assign": 90 }

- [Declarative policy syntax](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative_syntax.html)

- [Allowed AMIs (EC2)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-allowed-amis.html)          }#### Example: IMDSv2 required, endpoint enabled, tags enabled, hop limit 4

- [Manage Allowed AMIs settings](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/manage-settings-allowed-amis.html)

        }```json

---

      }{

> **Last Updated:** 2026-01-18  

> **Maintained By:** Prasa Cloud Platform Team    }  "ec2_attributes": {


  }    "instance_metadata_defaults": {

}      "http_tokens": { "@@assign": "required" },

```      "http_put_response_hop_limit": { "@@assign": "4" },

      "http_endpoint": { "@@assign": "enabled" },

### Criteria fields you can use (the allowlist "language")      "instance_metadata_tags": { "@@assign": "enabled" }

    }

Within each `criteria_N` (up to 10):  }

- `allowed_image_providers`  }

  Allowed owners: 12-digit account IDs or aliases like `amazon`, `aws_marketplace`, `aws_backup_vault`.```

- `image_names`  

  Supports wildcards `*` and `?`.---

- `marketplace_product_codes`  

  Allow specific Marketplace AMIs.# 4F) Snapshot Block Public Access (EBS snapshots)

- `creation_date_condition.maximum_days_since_created`  

  "Freshness" window.### What it controls

- `deprecation_time_condition.maximum_days_since_deprecated`  Whether EBS snapshots can be publicly shared.

  Time window after deprecation.

### Modes (`snapshot_block_public_access.state`)

### Prasa-specific guidance: how to choose criteria- **`unblocked`** → no restrictions

- **`block_new_sharing`** → blocks new public sharing; already-public remain public

| Phase | Criteria | Recommendation |- **`block_all_sharing`** → blocks all public sharing; already-public become private

|:------|:---------|:---------------|

| **Phase 1** | Provider allowlist | `["565656565656", "666363636363"]` (Prasa Ops accounts) |#### Example: block all public snapshot sharing

| **Phase 2** | Name patterns | Add `prasa-*` patterns after naming is stable |```json

| **Phase 3** | Age window | Add 60/90 days after patch cadence is reliable |{

| **Always** | Start with audit_mode | "audit_mode first" saves careers |  "ec2_attributes": {

    "snapshot_block_public_access": {

---      "state": { "@@assign": "block_all_sharing" }

    }

# 4E) Instance Metadata Defaults (IMDS defaults)  }

}

### What it controls```

Sets **defaults** for IMDS behavior for **new instance launches** (not a "hard enforcement" of every IMDS aspect, but it's still a powerful baseline).

---

### Fields and modes

## 5) Custom exception messages (developer experience)

#### `http_tokens`

- **`no_preference`** → other defaults apply (AMI defaults, etc.)You can define a single `exception_message` under `ec2_attributes` to return a helpful error when a noncompliant action fails.

- **`required`** → IMDSv2 required; IMDSv1 not allowed

- **`optional`** → IMDSv1 + IMDSv2 allowedExample:

```json

#### `http_endpoint`{

- **`no_preference`**  "ec2_attributes": {

- **`enabled`** → IMDS endpoint accessible    "exception_message": {

- **`disabled`** → IMDS endpoint not accessible      "@@assign": "AMI not approved. Use xyzzy-golden-* or request a time-bound exception via Jira."

    },

#### `instance_metadata_tags`    "allowed_images_settings": {

- **`no_preference`**      "state": { "@@assign": "enabled" }

- **`enabled`** → tags accessible via IMDS    }

- **`disabled`** → tags not accessible via IMDS  }

}

#### `http_put_response_hop_limit````

- Integer **-1 to 64**  

  - `-1` means "no preference"Keep it helpful, but don’t put secrets/PII in it.

  - If `http_tokens` is `required`, a hop limit of **>= 2** is typically recommended in real-world setups (containers, proxies, etc.).

---

#### Example: IMDSv2 required, endpoint enabled, tags enabled, hop limit 4

```json## 6) Limitations (what will surprise teams)

{

  "ec2_attributes": {### 6.1 Service-enforced behavior

    "instance_metadata_defaults": {- One setting can impact multiple APIs.

      "http_tokens": { "@@assign": "required" },- Noncompliant actions fail at the service level.

      "http_put_response_hop_limit": { "@@assign": "4" },- Account admins can’t change enforced attributes inside the account.

      "http_endpoint": { "@@assign": "enabled" },

      "instance_metadata_tags": { "@@assign": "enabled" }### 6.2 API restrictions (common)

    }When a setting is enforced by declarative policy, accounts typically can’t use the “enable/disable/reset” style API operations to modify it (examples include serial console enable/disable, image block public access enable/disable, allowed images settings enable/disable/replace criteria).

  }

}### 6.3 “Defaults” vs “Enforcement”

```Instance Metadata Defaults set defaults; they don’t retroactively rewrite existing instances, and don’t necessarily enforce every metadata behavior detail.



------



# 4F) Snapshot Block Public Access (EBS snapshots)## 7) Production-ready AMI governance pattern (recommended)



### What it controls### Phase 0 — Prep

Whether EBS snapshots can be publicly shared.- Establish golden AMI publishing pipeline (Packer, EC2 Image Builder, etc.)

- Adopt naming convention (e.g., `xyzzy-golden-<os>-<app>-<yyyy-mm-dd>`)

### Modes (`snapshot_block_public_access.state`)

- **`unblocked`** → no restrictions### Phase 1 — `audit_mode`

- **`block_new_sharing`** → blocks new public sharing; already-public remain public- Deploy Allowed AMIs in audit mode with provider allowlist + optional name pattern

- **`block_all_sharing`** → blocks all public sharing; already-public become private- Track findings; fix app teams



#### Example: block all public snapshot sharing (Prasa standard)### Phase 2 — `enabled` (enforcement)

```json- Flip to enabled after audits show low/no breakage

{- Keep exception process time-bound + approved

  "ec2_attributes": {

    "snapshot_block_public_access": {### Phase 3 — Harden the perimeter

      "state": { "@@assign": "block_all_sharing" }- Set Image Block Public Access to `block_new_sharing`

    }- Set Snapshot Block Public Access to `block_all_sharing` (or `block_new_sharing` if you need a gentler ramp)

  }

}---

```

## 8) GitOps: managing declarative policies via GitHub/GitLab

---

### 8.1 Repo structure (simple and effective)

## 5) Custom exception messages (developer experience)```

org-governance/

You can define a single `exception_message` under `ec2_attributes` to return a helpful error when a noncompliant action fails.  policies/

    ec2/

Example (Prasa custom message):      allowed-amis.audit.json

```json      allowed-amis.enforced.json

{      image-block-public-access.json

  "ec2_attributes": {      snapshot-block-public-access.json

    "exception_message": {  scripts/

      "@@assign": "AMI not approved for use in Prasa organization. Only prasa-* AMIs from Operations accounts (prasains-operations-dev-use2, prasains-operations-prd-use2) are permitted. Approved patterns: prasa-rhel8-*, prasa-rhel9-*, prasa-win16-*, prasa-win19-*, prasa-win22-*, prasa-al2023-*, prasa-al2-2024-*, prasa-mlal2-*, prasa-opsdir-mlal2-*. To request an exception, submit a Jira ticket."    validate-json.sh

    },  .gitlab-ci.yml

    "allowed_images_settings": {  README.md

      "state": { "@@assign": "enabled" }```

    }

  }### 8.2 GitLab CI/CD pipeline idea (minimum viable)

}Stages:

```1. **Validate** JSON formatting + basic schema checks

2. **Plan**: show diff between current effective policy and proposed

Keep it helpful, but don't put secrets/PII in it.3. **Apply**: update policy + attach

4. **Verify**: `describe-effective-policy` gate

---

Pseudo `.gitlab-ci.yml` skeleton:

## 6) Limitations (what will surprise teams)```yaml

stages: [validate, apply, verify]

### 6.1 Service-enforced behavior

- One setting can impact multiple APIs.validate:

- Noncompliant actions fail at the service level.  stage: validate

- Account admins can't change enforced attributes inside the account.  image: amazon/aws-cli:2

  script:

### 6.2 API restrictions (common)    - ./scripts/validate-json.sh policies/ec2/*.json

When a setting is enforced by declarative policy, accounts typically can't use the "enable/disable/reset" style API operations to modify it (examples include serial console enable/disable, image block public access enable/disable, allowed images settings enable/disable/replace criteria).

apply:

### 6.3 "Defaults" vs "Enforcement"  stage: apply

Instance Metadata Defaults set defaults; they don't retroactively rewrite existing instances, and don't necessarily enforce every metadata behavior detail.  image: amazon/aws-cli:2

  script:

---    - aws organizations update-policy --policy-id "$POLICY_ID" --content file://policies/ec2/allowed-amis.audit.json



## 7) Production-ready AMI governance pattern (Prasa recommended)verify:

  stage: verify

### Phase 0 — Prep  image: amazon/aws-cli:2

- ✅ Establish golden AMI publishing pipeline (Packer, EC2 Image Builder, etc.)  script:

- ✅ Adopt naming convention: `prasa-{os}-{version}-{date}-{build}`    - aws organizations describe-effective-policy --policy-type DECLARATIVE_POLICY_EC2 --target-id "$TARGET_ACCOUNT" > effective.json

- ✅ Publish from Operations accounts only:    - cat effective.json

  - `565656565656` (prasains-operations-dev-use2)```

  - `666363636363` (prasains-operations-prd-use2)

**Auth best practice:** use short-lived credentials (OIDC federation) rather than long-lived keys.

### Phase 1 — `audit_mode`

- Deploy Allowed AMIs in audit mode with Prasa provider allowlist---

- Add name patterns: `prasa-*`

- Track findings; fix app teams## 9) Handy reference links (AWS docs + examples)



```json### AWS documentation

{- Declarative policies overview (Organizations): https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html

  "ec2_attributes": {- Declarative policy syntax + supported EC2 attributes: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative_syntax.html

    "allowed_images_settings": {- Inheritance operators: https://docs.aws.amazon.com/organizations/latest/userguide/policy-operators.html

      "state": { "@@assign": "audit_mode" },- Allowed AMIs (EC2): https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-allowed-amis.html

      "image_criteria": {- Manage Allowed AMIs settings (EC2 console workflow): https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/manage-settings-allowed-amis.html

        "criteria_1": {- Organizations CLI `describe-effective-policy`: https://docs.aws.amazon.com/cli/latest/reference/organizations/describe-effective-policy.html

          "allowed_image_providers": { 

            "@@assign": ["565656565656", "666363636363"] ### GitHub examples (policy-as-code patterns)

          }- aws-samples/organizations-policy-pipeline: https://github.com/aws-samples/organizations-policy-pipeline

        }- aws-samples/terraform-aws-organization-policies: https://github.com/aws-samples/terraform-aws-organization-policies

      }

    }### GitLab references

  }- GitLab docs: Deploy to AWS from GitLab CI/CD: https://docs.gitlab.com/ee/ci/cloud_services/aws/

}- GitLab docs: OpenID Connect in CI/CD (for AWS federation): https://docs.gitlab.com/ee/ci/secrets/id_token_authentication.html

```

---

### Phase 2 — `enabled` (enforcement)

- Flip to enabled after audits show low/no breakage## 10) Quick “mid-level engineer” cheat sheet

- Keep exception process time-bound + approved

**If your goal is “restrict AMIs safely”:**

```json1. Start with `allowed_images_settings.state = audit_mode`

{2. Criteria: allow only your golden AMI publisher account (and optionally `amazon`)

  "ec2_attributes": {3. Add `image_names` pattern after naming is stable

    "allowed_images_settings": {4. Add `maximum_days_since_created` after patch cadence is reliable

      "@@operators_allowed_for_child_policies": ["@@none"],5. Flip to `enabled`

      "state": { "@@assign": "enabled" },6. Lock down child OUs with `@@operators_allowed_for_child_policies`

      "image_criteria": {7. Add Image Block Public Access = `block_new_sharing` and Snapshot Block Public Access = `block_all_sharing`

        "criteria_1": {

          "allowed_image_providers": { ---

            "@@assign": ["565656565656", "666363636363"] 

          },_End of file_

          "image_names": { 
            "@@assign": [
              "prasa-rhel8-*",
              "prasa-rhel9-*",
              "prasa-win16-*",
              "prasa-win19-*",
              "prasa-win22-*",
              "prasa-al2023-*",
              "prasa-al2-2024-*",
              "prasa-mlal2-*",
              "prasa-opsdir-mlal2-*"
            ] 
          }
        }
      }
    }
  }
}
```

### Phase 3 — Harden the perimeter
- Set Image Block Public Access to `block_new_sharing`
- Set Snapshot Block Public Access to `block_all_sharing`

---

## 8) GitOps: managing declarative policies via GitHub/GitLab

### 8.1 Repo structure (Prasa recommended)
```
aws-service-control-policies/
  policies/
    scp-ami-guardrail-2026-01-18.json
    declarative-policy-ec2-2026-01-18.json
  environments/
    dev/
      main.tf
      variables.tf
    prd/
      main.tf
      variables.tf
  modules/
    organizations/
      main.tf
      variables.tf
      outputs.tf
  doc/
    AMI-GOVERNANCE-README.md
  .gitlab-ci.yml
  README.md
```

### 8.2 GitLab CI/CD pipeline idea (minimum viable)
Stages:
1. **Validate** JSON formatting + basic schema checks
2. **Plan**: show diff between current effective policy and proposed
3. **Apply**: update policy + attach
4. **Verify**: `describe-effective-policy` gate

Pseudo `.gitlab-ci.yml` skeleton:
```yaml
stages: [validate, plan, apply, verify]

validate:
  stage: validate
  image: amazon/aws-cli:2
  script:
    - ./scripts/validate-json.sh policies/*.json

plan:
  stage: plan
  image: hashicorp/terraform:latest
  script:
    - cd environments/dev
    - terraform init
    - terraform plan

apply:
  stage: apply
  image: hashicorp/terraform:latest
  script:
    - cd environments/dev
    - terraform apply -auto-approve
  when: manual

verify:
  stage: verify
  image: amazon/aws-cli:2
  script:
    - aws organizations describe-effective-policy --policy-type DECLARATIVE_POLICY_EC2 --target-id "$TARGET_ACCOUNT" > effective.json
    - cat effective.json
```

**Auth best practice:** use short-lived credentials (OIDC federation) rather than long-lived keys.

---

## 9) Handy reference links (AWS docs + examples)

### AWS documentation
- Declarative policies overview (Organizations): https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html
- Declarative policy syntax + supported EC2 attributes: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative_syntax.html
- Inheritance operators: https://docs.aws.amazon.com/organizations/latest/userguide/policy-operators.html
- Allowed AMIs (EC2): https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-allowed-amis.html
- Manage Allowed AMIs settings (EC2 console workflow): https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/manage-settings-allowed-amis.html
- Organizations CLI `describe-effective-policy`: https://docs.aws.amazon.com/cli/latest/reference/organizations/describe-effective-policy.html

### GitHub examples (policy-as-code patterns)
- aws-samples/organizations-policy-pipeline: https://github.com/aws-samples/organizations-policy-pipeline
- aws-samples/terraform-aws-organization-policies: https://github.com/aws-samples/terraform-aws-organization-policies

### GitLab references
- GitLab docs: Deploy to AWS from GitLab CI/CD: https://docs.gitlab.com/ee/ci/cloud_services/aws/
- GitLab docs: OpenID Connect in CI/CD (for AWS federation): https://docs.gitlab.com/ee/ci/secrets/id_token_authentication.html

---

## 10) Quick "Prasa Platform Engineer" cheat sheet

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

### Rollout Checklist

**If your goal is "restrict AMIs safely" in Prasa org:**

1. ✅ Start with `allowed_images_settings.state = audit_mode`
2. ✅ Criteria: allow only Prasa Operations accounts (`565656565656`, `666363636363`)
3. ✅ Add `image_names` patterns: `prasa-*`
4. ✅ Add `maximum_days_since_created` after patch cadence is reliable (60-90 days)
5. ✅ Flip to `enabled`
6. ✅ Lock down child OUs with `@@operators_allowed_for_child_policies: ["@@none"]`
7. ✅ Add Image Block Public Access = `block_new_sharing`
8. ✅ Add Snapshot Block Public Access = `block_all_sharing`

### Useful AWS CLI Commands

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

# Find RHEL 9 AMIs
aws ec2 describe-images \
  --owners 565656565656 666363636363 \
  --filters "Name=name,Values=prasa-rhel9-*" \
  --query 'Images[*].[Name,ImageId,CreationDate]' \
  --output table

# Check effective policy for an account
aws organizations describe-effective-policy \
  --policy-type DECLARATIVE_POLICY_EC2 \
  --target-id <account-id>
```

---

## 11) Complete Prasa Declarative Policy Example

This is the full production-ready declarative policy for Prasa:

```json
{
  "ec2_attributes": {
    "@@operators_allowed_for_child_policies": ["@@none"],
    
    "exception_message": {
      "@@assign": "AMI not approved for use in Prasa organization. Only prasa-* AMIs from Operations accounts (prasains-operations-dev-use2: 565656565656, prasains-operations-prd-use2: 666363636363) are permitted. Approved patterns: prasa-rhel8-*, prasa-rhel9-*, prasa-win16-*, prasa-win19-*, prasa-win22-*, prasa-al2023-*, prasa-al2-2024-*, prasa-mlal2-*, prasa-opsdir-mlal2-*. To request an exception, submit a Jira ticket."
    },
    
    "image_block_public_access": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      "state": { "@@assign": "block_new_sharing" }
    },
    
    "snapshot_block_public_access": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      "state": { "@@assign": "block_all_sharing" }
    },
    
    "allowed_images_settings": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      "state": { "@@assign": "audit_mode" },
      "image_criteria": {
        "criteria_1": {
          "allowed_image_providers": {
            "@@assign": ["565656565656", "666363636363"]
          },
          "image_names": {
            "@@assign": [
              "prasa-rhel8-*",
              "prasa-rhel9-*",
              "prasa-win16-*",
              "prasa-win19-*",
              "prasa-win22-*",
              "prasa-al2023-*",
              "prasa-al2-2024-*",
              "prasa-mlal2-*",
              "prasa-opsdir-mlal2-*"
            ]
          }
        }
      }
    },
    
    "instance_metadata_defaults": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      "http_tokens": { "@@assign": "required" },
      "http_put_response_hop_limit": { "@@assign": "2" },
      "http_endpoint": { "@@assign": "enabled" },
      "instance_metadata_tags": { "@@assign": "enabled" }
    },
    
    "serial_console_access": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      "status": { "@@assign": "disabled" }
    }
  }
}
```

---

_End of file_

> **Last Updated:** 2026-01-18  
> **Maintained By:** Prasa Cloud Platform Team
