# EC2 Declarative Policies (AWS Organizations) — Field Guide for Platform Engineers# EC2 Declarative Policies (AWS Organizations) — Field Guide for Platform Engineers



> **Purpose:** This is a **mid-level** "how it actually works in practice" guide to **EC2 declarative policies** in AWS Organizations, with special focus on **AMI restriction (Allowed AMIs / Allowed Images Settings)** and the **modes** each attribute supports.> Purpose: This is a **mid-level** “how it actually works in practice” guide to **EC2 declarative policies** in AWS Organizations, with special focus on **AMI restriction (Allowed AMIs / Allowed Images Settings)** and the **modes** each attribute supports.

>

> **Updated:** 2026-01-18 | **Organization:** Prasa---



---## 1) What declarative policies are



## Prasa Operations Quick Reference**Declarative policies** are an AWS Organizations policy type that lets you centrally **declare and enforce EC2 account-attribute configuration** across accounts/OUs/root. Unlike SCPs (authorization-time allow/deny), declarative policies are **enforced by the service control plane**. That means:



### Approved AMI Publisher Accounts- The service maintains the “desired state” configuration you declare.

- **Noncompliant actions fail** at the service level.

| Account ID | Account Alias | Environment | Region |- Account admins generally **can’t override** an attribute that’s enforced by declarative policy.

|:----------:|:--------------|:-----------:|:------:|

| `565656565656` | prasains-operations-dev-use2 | DEV | us-east-2 |**Why you’d use it:** governance that’s closer to “configuration management” than “permissions management”, especially for settings that can’t be reliably controlled with IAM conditions alone.

| `666363636363` | prasains-operations-prd-use2 | PRD | us-east-2 |

---

### Approved AMI Patterns

## 2) How to use EC2 declarative policies (practical workflow)

| Category | AMI Name Patterns | AMI Aliases |

|:---------|:------------------|:------------|### 2.1 High-level rollout (recommended)

| **MarkLogic** | `prasa-opsdir-mlal2-*`, `prasa-mlal2-*` | `prasa-OPSDIR-MLAL2-CF`, `prasa-MLAL2-CF` |1. **Generate an account status report** (inventory current config across the org)

| **RHEL** | `prasa-rhel8-*`, `prasa-rhel9-*` | `prasa-rhel8-cf`, `prasa-rhel9-cf` |2. Start with a **pilot OU/account**

| **Windows** | `prasa-win16-*`, `prasa-win19-*`, `prasa-win22-*` | `prasa-win16-cf`, `prasa-win19-cf`, `prasa-win22-cf` |3. Validate the **effective policy** on a target account

| **Amazon Linux** | `prasa-al2023-*`, `prasa-al2-2024-*` | `prasa-al2023-cf`, `prasa-al2-2024-cf` |4. Expand to broader OUs / root



---### 2.2 Where you attach

You can attach policies to:

## 1) What declarative policies are- Organization **root**

- an **OU**

**Declarative policies** are an AWS Organizations policy type that lets you centrally **declare and enforce EC2 account-attribute configuration** across accounts/OUs/root. Unlike SCPs (authorization-time allow/deny), declarative policies are **enforced by the service control plane**. That means:- an **account**



- The service maintains the "desired state" configuration you declare.### 2.3 “Effective policy” (your safety rail)

- **Noncompliant actions fail** at the service level.In AWS Organizations, the **effective policy** for an account is the combination of inherited policies + directly attached policy (for the given policy type). You should treat “DescribeEffectivePolicy” as a required validation step in CI/CD.

- Account admins generally **can't override** an attribute that's enforced by declarative policy.

---

**Why you'd use it:** governance that's closer to "configuration management" than "permissions management", especially for settings that can't be reliably controlled with IAM conditions alone.

## 3) Syntax essentials (and the inheritance operators)

---

A declarative policy is **JSON** and starts with the fixed top-level key:

## 2) How to use EC2 declarative policies (practical workflow)

```json

### 2.1 High-level rollout (recommended){

1. **Generate an account status report** (inventory current config across the org)  "ec2_attributes": {

2. Start with a **pilot OU/account**    "...": {}

3. Validate the **effective policy** on a target account  }

4. Expand to broader OUs / root}

```

### 2.2 Where you attach

You can attach policies to:### 3.1 Value-setting operators

- Organization **root**Declarative policies use the same value-setting operators as other Organizations management policy types:

- an **OU**

- an **account**- `@@assign` → set/overwrite a value

- `@@append` → add values to a list inherited from parents

### 2.3 "Effective policy" (your safety rail)- `@@remove` → remove specific values from an inherited list

In AWS Organizations, the **effective policy** for an account is the combination of inherited policies + directly attached policy (for the given policy type). You should treat "DescribeEffectivePolicy" as a required validation step in CI/CD.

Example:

---

```json

## 3) Syntax essentials (and the inheritance operators){

  "ec2_attributes": {

A declarative policy is **JSON** and starts with the fixed top-level key:    "allowed_images_settings": {

      "image_criteria": {

```json        "criteria_1": {

{          "allowed_image_providers": {

  "ec2_attributes": {            "@@append": ["amazon", "111122223333"]

    "...": {}          }

  }        }

}      }

```    }

  }

### 3.1 Value-setting operators}

Declarative policies use the same value-setting operators as other Organizations management policy types:```



- `@@assign` → set/overwrite a value### 3.2 Controlling what child OUs/accounts can do

- `@@append` → add values to a list inherited from parentsUse `@@operators_allowed_for_child_policies` to restrict what descendants can do.

- `@@remove` → remove specific values from an inherited list

- `["@@none"]` → children can’t change that subtree

Example (Prasa Operations accounts):- Or allow only some ops, like `["@@append"]` if you want children to add to a list but not overwrite it



```jsonExample (lock it down):

{

  "ec2_attributes": {```json

    "allowed_images_settings": {{

      "image_criteria": {  "ec2_attributes": {

        "criteria_1": {    "allowed_images_settings": {

          "allowed_image_providers": {      "@@operators_allowed_for_child_policies": ["@@none"],

            "@@assign": ["565656565656", "666363636363"]      "state": { "@@assign": "enabled" }

          }    }

        }  }

      }}

    }```

  }

}---

```

## 4) The EC2 attributes you can control (and their modes)

### 3.2 Controlling what child OUs/accounts can do

Use `@@operators_allowed_for_child_policies` to restrict what descendants can do.AWS Organizations currently supports these EC2-related attributes in declarative policies:



- `["@@none"]` → children can't change that subtree- **VPC Block Public Access**

- Or allow only some ops, like `["@@append"]` if you want children to add to a list but not overwrite it- **Serial Console Access**

- **Image Block Public Access**

Example (lock it down for Prasa):- **Allowed Images Settings** (Allowed AMIs)

- **Instance Metadata Defaults** (IMDS defaults)

```json- **Snapshot Block Public Access**

{

  "ec2_attributes": {This section explains **each attribute’s modes/states**, what they mean, and gives a practical example.

    "allowed_images_settings": {

      "@@operators_allowed_for_child_policies": ["@@none"],---

      "state": { "@@assign": "enabled" },

      "image_criteria": {# 4A) VPC Block Public Access (VPC BPA)

        "criteria_1": {

          "allowed_image_providers": {### What it controls

            "@@assign": ["565656565656", "666363636363"]Whether VPC/subnet resources can reach the internet through internet gateways (IGWs), via an account-level VPC Block Public Access mode.

          }

        }### Modes (`internet_gateway_block.mode`)

      }- **`off`**  

    }  VPC BPA is not enabled.

  }

}- **`block_ingress`**  

```  Blocks inbound internet traffic to VPCs (except excluded VPCs/subnets). NAT gateways and egress-only IGWs still allow outbound connections because they’re outbound-initiated.



---- **`block_bidirectional`**  

  Blocks both inbound and outbound via IGWs/egress-only IGWs (except excluded VPCs/subnets).

## 4) The EC2 attributes you can control (and their modes)

### Exclusions (`internet_gateway_block.exclusions_allowed`)

AWS Organizations currently supports these EC2-related attributes in declarative policies:- **`enabled`** → accounts may create exclusions

- **`disabled`** → accounts may not create exclusions

- **VPC Block Public Access**

- **Serial Console Access**> Important: the policy can allow/disallow exclusions, but **does not create exclusions**. Exclusions are created inside the owning account.

- **Image Block Public Access**

- **Allowed Images Settings** (Allowed AMIs)#### Example: block ingress, allow exclusions

- **Instance Metadata Defaults** (IMDS defaults)```json

- **Snapshot Block Public Access**{

  "ec2_attributes": {

This section explains **each attribute's modes/states**, what they mean, and gives a practical example.    "vpc_block_public_access": {

      "internet_gateway_block": {

---        "mode": { "@@assign": "block_ingress" },

        "exclusions_allowed": { "@@assign": "enabled" }

# 4A) VPC Block Public Access (VPC BPA)      }

    }

### What it controls  }

Whether VPC/subnet resources can reach the internet through internet gateways (IGWs), via an account-level VPC Block Public Access mode.}

```

### Modes (`internet_gateway_block.mode`)

- **`off`**  ---

  VPC BPA is not enabled.

# 4B) Serial Console Access

- **`block_ingress`**  

  Blocks inbound internet traffic to VPCs (except excluded VPCs/subnets). NAT gateways and egress-only IGWs still allow outbound connections because they're outbound-initiated.### What it controls

Whether the EC2 Serial Console is accessible.

- **`block_bidirectional`**  

  Blocks both inbound and outbound via IGWs/egress-only IGWs (except excluded VPCs/subnets).### Modes (`serial_console_access.status`)

- **`enabled`** → serial console allowed

### Exclusions (`internet_gateway_block.exclusions_allowed`)- **`disabled`** → serial console blocked

- **`enabled`** → accounts may create exclusions

- **`disabled`** → accounts may not create exclusions#### Example: disable serial console

```json

> Important: the policy can allow/disallow exclusions, but **does not create exclusions**. Exclusions are created inside the owning account.{

  "ec2_attributes": {

#### Example: block ingress, allow exclusions    "serial_console_access": {

```json      "status": { "@@assign": "disabled" }

{    }

  "ec2_attributes": {  }

    "vpc_block_public_access": {}

      "internet_gateway_block": {```

        "mode": { "@@assign": "block_ingress" },

        "exclusions_allowed": { "@@assign": "enabled" }---

      }

    }# 4C) Image Block Public Access (AMI public sharing guardrail)

  }

}### What it controls

```Whether AMIs can be publicly shared (public launch permissions).



---### Modes (`image_block_public_access.state`)

- **`unblocked`**  

# 4B) Serial Console Access  No restrictions. Accounts can publicly share new AMIs.



### What it controls- **`block_new_sharing`**  

Whether the EC2 Serial Console is accessible.  Prevents **new** public sharing. AMIs that are *already* public remain public.



### Modes (`serial_console_access.status`)#### Example: stop new public AMI sharing

- **`enabled`** → serial console allowed```json

- **`disabled`** → serial console blocked{

  "ec2_attributes": {

#### Example: disable serial console    "image_block_public_access": {

```json      "state": { "@@assign": "block_new_sharing" }

{    }

  "ec2_attributes": {  }

    "serial_console_access": {}

      "status": { "@@assign": "disabled" }```

    }

  }---

}

```# 4D) Allowed Images Settings (Allowed AMIs) — the AMI restriction engine



---### What it controls

Controls the **discovery and use** of AMIs in EC2 by defining a central allowlist (criteria).

# 4C) Image Block Public Access (AMI public sharing guardrail)

### The 3 operational modes (`allowed_images_settings.state`)

### What it controls

Whether AMIs can be publicly shared (public launch permissions).#### Mode 1 — `disabled`

**Meaning:** No enforcement; no compliance evaluation.  

### Modes (`image_block_public_access.state`)**When you use it:** during rollout rollback, or if you’re not ready to constrain AMIs.

- **`unblocked`**  

  No restrictions. Accounts can publicly share new AMIs.**Example:**

```json

- **`block_new_sharing`**  {

  Prevents **new** public sharing. AMIs that are *already* public remain public.  "ec2_attributes": {

    "allowed_images_settings": {

#### Example: stop new public AMI sharing (Prasa standard)      "state": { "@@assign": "disabled" }

```json    }

{  }

  "ec2_attributes": {}

    "image_block_public_access": {```

      "state": { "@@assign": "block_new_sharing" }

    }#### Mode 2 — `audit_mode`

  }**Meaning:** **Do not block** usage, but **identify** whether AMIs would be allowed by your criteria.  

}**When you use it:** the first phase of rollout to find breakage before enforcement.

```

**What you’ll observe:**  

---- APIs like `DescribeImages` can include an `imageAllowed` style signal in results when in audit mode (service-side behavior depends on API; the core idea is “tagging” vs “blocking”).

- Workloads still run, but you can detect “would fail later” cases.

# 4D) Allowed Images Settings (Allowed AMIs) — the AMI restriction engine

**Example:**

### What it controls```json

Controls the **discovery and use** of AMIs in EC2 by defining a central allowlist (criteria).{

  "ec2_attributes": {

### The 3 operational modes (`allowed_images_settings.state`)    "allowed_images_settings": {

      "state": { "@@assign": "audit_mode" },

#### Mode 1 — `disabled`      "image_criteria": {

**Meaning:** No enforcement; no compliance evaluation.          "criteria_1": {

**When you use it:** during rollout rollback, or if you're not ready to constrain AMIs.          "allowed_image_providers": { "@@assign": ["amazon", "111122223333"] },

          "image_names": { "@@assign": ["xyzzy-golden-*"] }

**Example:**        }

```json      }

{    }

  "ec2_attributes": {  }

    "allowed_images_settings": {}

      "state": { "@@assign": "disabled" }```

    }

  }#### Mode 3 — `enabled`

}**Meaning:** **Enforced**. Only images that match your criteria are allowed/discoverable/usable (per Allowed AMIs behavior).  

```**When you use it:** after audit mode proves teams are compliant.



#### Mode 2 — `audit_mode`**Example:**

**Meaning:** **Do not block** usage, but **identify** whether AMIs would be allowed by your criteria.  ```json

**When you use it:** the first phase of rollout to find breakage before enforcement.{

  "ec2_attributes": {

**What you'll observe:**      "allowed_images_settings": {

- APIs like `DescribeImages` can include an `imageAllowed` style signal in results when in audit mode (service-side behavior depends on API; the core idea is "tagging" vs "blocking").      "state": { "@@assign": "enabled" },

- Workloads still run, but you can detect "would fail later" cases.      "image_criteria": {

        "criteria_1": {

**Example (Prasa Operations - audit mode):**          "allowed_image_providers": { "@@assign": ["111122223333"] },

```json          "image_names": { "@@assign": ["xyzzy-golden-*"] },

{          "creation_date_condition": {

  "ec2_attributes": {            "maximum_days_since_created": { "@@assign": 90 }

    "allowed_images_settings": {          }

      "state": { "@@assign": "audit_mode" },        }

      "image_criteria": {      }

        "criteria_1": {    }

          "allowed_image_providers": {   }

            "@@assign": ["565656565656", "666363636363"] }

          },```

          "image_names": { 

            "@@assign": [### Criteria fields you can use (the allowlist “language”)

              "prasa-rhel8-*",

              "prasa-rhel9-*",Within each `criteria_N` (up to 10):

              "prasa-win16-*",- `allowed_image_providers`  

              "prasa-win19-*",  Allowed owners: 12-digit account IDs or aliases like `amazon`, `aws_marketplace`, `aws_backup_vault`.

              "prasa-win22-*",- `image_names`  

              "prasa-al2023-*",  Supports wildcards `*` and `?`.

              "prasa-al2-2024-*",- `marketplace_product_codes`  

              "prasa-mlal2-*",  Allow specific Marketplace AMIs.

              "prasa-opsdir-mlal2-*"- `creation_date_condition.maximum_days_since_created`  

            ]   “Freshness” window.

          }- `deprecation_time_condition.maximum_days_since_deprecated`  

        }  Time window after deprecation.

      }

    }### Practical mid-level guidance: how to choose criteria

  }- Start with **provider allowlist** (your golden AMI publishing account + `amazon` if needed).

}- Add **name patterns** once you have a stable convention.

```- Add **age window** (like 60/90 days) after patch cadence is reliable.

- Avoid making criteria too clever early—“audit_mode first” saves careers.

#### Mode 3 — `enabled`

**Meaning:** **Enforced**. Only images that match your criteria are allowed/discoverable/usable (per Allowed AMIs behavior).  ---

**When you use it:** after audit mode proves teams are compliant.

# 4E) Instance Metadata Defaults (IMDS defaults)

**Example (Prasa Operations - enforced with age limit):**

```json### What it controls

{Sets **defaults** for IMDS behavior for **new instance launches** (not a “hard enforcement” of every IMDS aspect, but it’s still a powerful baseline).

  "ec2_attributes": {

    "allowed_images_settings": {### Fields and modes

      "state": { "@@assign": "enabled" },

      "image_criteria": {#### `http_tokens`

        "criteria_1": {- **`no_preference`** → other defaults apply (AMI defaults, etc.)

          "allowed_image_providers": { - **`required`** → IMDSv2 required; IMDSv1 not allowed

            "@@assign": ["565656565656", "666363636363"] - **`optional`** → IMDSv1 + IMDSv2 allowed

          },

          "image_names": { #### `http_endpoint`

            "@@assign": [- **`no_preference`**

              "prasa-rhel8-*",- **`enabled`** → IMDS endpoint accessible

              "prasa-rhel9-*",- **`disabled`** → IMDS endpoint not accessible

              "prasa-win16-*",

              "prasa-win19-*",#### `instance_metadata_tags`

              "prasa-win22-*",- **`no_preference`**

              "prasa-al2023-*",- **`enabled`** → tags accessible via IMDS

              "prasa-al2-2024-*",- **`disabled`** → tags not accessible via IMDS

              "prasa-mlal2-*",

              "prasa-opsdir-mlal2-*"#### `http_put_response_hop_limit`

            ] - Integer **-1 to 64**  

          },  - `-1` means “no preference”

          "creation_date_condition": {  - If `http_tokens` is `required`, a hop limit of **>= 2** is typically recommended in real-world setups (containers, proxies, etc.).

            "maximum_days_since_created": { "@@assign": 90 }

          }#### Example: IMDSv2 required, endpoint enabled, tags enabled, hop limit 4

        }```json

      }{

    }  "ec2_attributes": {

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
