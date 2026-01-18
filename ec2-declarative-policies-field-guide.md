# EC2 Declarative Policies (AWS Organizations) — Field Guide for Platform Engineers

> Purpose: This is a **mid-level** “how it actually works in practice” guide to **EC2 declarative policies** in AWS Organizations, with special focus on **AMI restriction (Allowed AMIs / Allowed Images Settings)** and the **modes** each attribute supports.

---

## 1) What declarative policies are

**Declarative policies** are an AWS Organizations policy type that lets you centrally **declare and enforce EC2 account-attribute configuration** across accounts/OUs/root. Unlike SCPs (authorization-time allow/deny), declarative policies are **enforced by the service control plane**. That means:

- The service maintains the “desired state” configuration you declare.
- **Noncompliant actions fail** at the service level.
- Account admins generally **can’t override** an attribute that’s enforced by declarative policy.

**Why you’d use it:** governance that’s closer to “configuration management” than “permissions management”, especially for settings that can’t be reliably controlled with IAM conditions alone.

---

## 2) How to use EC2 declarative policies (practical workflow)

### 2.1 High-level rollout (recommended)
1. **Generate an account status report** (inventory current config across the org)
2. Start with a **pilot OU/account**
3. Validate the **effective policy** on a target account
4. Expand to broader OUs / root

### 2.2 Where you attach
You can attach policies to:
- Organization **root**
- an **OU**
- an **account**

### 2.3 “Effective policy” (your safety rail)
In AWS Organizations, the **effective policy** for an account is the combination of inherited policies + directly attached policy (for the given policy type). You should treat “DescribeEffectivePolicy” as a required validation step in CI/CD.

---

## 3) Syntax essentials (and the inheritance operators)

A declarative policy is **JSON** and starts with the fixed top-level key:

```json
{
  "ec2_attributes": {
    "...": {}
  }
}
```

### 3.1 Value-setting operators
Declarative policies use the same value-setting operators as other Organizations management policy types:

- `@@assign` → set/overwrite a value
- `@@append` → add values to a list inherited from parents
- `@@remove` → remove specific values from an inherited list

Example:

```json
{
  "ec2_attributes": {
    "allowed_images_settings": {
      "image_criteria": {
        "criteria_1": {
          "allowed_image_providers": {
            "@@append": ["amazon", "111122223333"]
          }
        }
      }
    }
  }
}
```

### 3.2 Controlling what child OUs/accounts can do
Use `@@operators_allowed_for_child_policies` to restrict what descendants can do.

- `["@@none"]` → children can’t change that subtree
- Or allow only some ops, like `["@@append"]` if you want children to add to a list but not overwrite it

Example (lock it down):

```json
{
  "ec2_attributes": {
    "allowed_images_settings": {
      "@@operators_allowed_for_child_policies": ["@@none"],
      "state": { "@@assign": "enabled" }
    }
  }
}
```

---

## 4) The EC2 attributes you can control (and their modes)

AWS Organizations currently supports these EC2-related attributes in declarative policies:

- **VPC Block Public Access**
- **Serial Console Access**
- **Image Block Public Access**
- **Allowed Images Settings** (Allowed AMIs)
- **Instance Metadata Defaults** (IMDS defaults)
- **Snapshot Block Public Access**

This section explains **each attribute’s modes/states**, what they mean, and gives a practical example.

---

# 4A) VPC Block Public Access (VPC BPA)

### What it controls
Whether VPC/subnet resources can reach the internet through internet gateways (IGWs), via an account-level VPC Block Public Access mode.

### Modes (`internet_gateway_block.mode`)
- **`off`**  
  VPC BPA is not enabled.

- **`block_ingress`**  
  Blocks inbound internet traffic to VPCs (except excluded VPCs/subnets). NAT gateways and egress-only IGWs still allow outbound connections because they’re outbound-initiated.

- **`block_bidirectional`**  
  Blocks both inbound and outbound via IGWs/egress-only IGWs (except excluded VPCs/subnets).

### Exclusions (`internet_gateway_block.exclusions_allowed`)
- **`enabled`** → accounts may create exclusions
- **`disabled`** → accounts may not create exclusions

> Important: the policy can allow/disallow exclusions, but **does not create exclusions**. Exclusions are created inside the owning account.

#### Example: block ingress, allow exclusions
```json
{
  "ec2_attributes": {
    "vpc_block_public_access": {
      "internet_gateway_block": {
        "mode": { "@@assign": "block_ingress" },
        "exclusions_allowed": { "@@assign": "enabled" }
      }
    }
  }
}
```

---

# 4B) Serial Console Access

### What it controls
Whether the EC2 Serial Console is accessible.

### Modes (`serial_console_access.status`)
- **`enabled`** → serial console allowed
- **`disabled`** → serial console blocked

#### Example: disable serial console
```json
{
  "ec2_attributes": {
    "serial_console_access": {
      "status": { "@@assign": "disabled" }
    }
  }
}
```

---

# 4C) Image Block Public Access (AMI public sharing guardrail)

### What it controls
Whether AMIs can be publicly shared (public launch permissions).

### Modes (`image_block_public_access.state`)
- **`unblocked`**  
  No restrictions. Accounts can publicly share new AMIs.

- **`block_new_sharing`**  
  Prevents **new** public sharing. AMIs that are *already* public remain public.

#### Example: stop new public AMI sharing
```json
{
  "ec2_attributes": {
    "image_block_public_access": {
      "state": { "@@assign": "block_new_sharing" }
    }
  }
}
```

---

# 4D) Allowed Images Settings (Allowed AMIs) — the AMI restriction engine

### What it controls
Controls the **discovery and use** of AMIs in EC2 by defining a central allowlist (criteria).

### The 3 operational modes (`allowed_images_settings.state`)

#### Mode 1 — `disabled`
**Meaning:** No enforcement; no compliance evaluation.  
**When you use it:** during rollout rollback, or if you’re not ready to constrain AMIs.

**Example:**
```json
{
  "ec2_attributes": {
    "allowed_images_settings": {
      "state": { "@@assign": "disabled" }
    }
  }
}
```

#### Mode 2 — `audit_mode`
**Meaning:** **Do not block** usage, but **identify** whether AMIs would be allowed by your criteria.  
**When you use it:** the first phase of rollout to find breakage before enforcement.

**What you’ll observe:**  
- APIs like `DescribeImages` can include an `imageAllowed` style signal in results when in audit mode (service-side behavior depends on API; the core idea is “tagging” vs “blocking”).
- Workloads still run, but you can detect “would fail later” cases.

**Example:**
```json
{
  "ec2_attributes": {
    "allowed_images_settings": {
      "state": { "@@assign": "audit_mode" },
      "image_criteria": {
        "criteria_1": {
          "allowed_image_providers": { "@@assign": ["amazon", "111122223333"] },
          "image_names": { "@@assign": ["xyzzy-golden-*"] }
        }
      }
    }
  }
}
```

#### Mode 3 — `enabled`
**Meaning:** **Enforced**. Only images that match your criteria are allowed/discoverable/usable (per Allowed AMIs behavior).  
**When you use it:** after audit mode proves teams are compliant.

**Example:**
```json
{
  "ec2_attributes": {
    "allowed_images_settings": {
      "state": { "@@assign": "enabled" },
      "image_criteria": {
        "criteria_1": {
          "allowed_image_providers": { "@@assign": ["111122223333"] },
          "image_names": { "@@assign": ["xyzzy-golden-*"] },
          "creation_date_condition": {
            "maximum_days_since_created": { "@@assign": 90 }
          }
        }
      }
    }
  }
}
```

### Criteria fields you can use (the allowlist “language”)

Within each `criteria_N` (up to 10):
- `allowed_image_providers`  
  Allowed owners: 12-digit account IDs or aliases like `amazon`, `aws_marketplace`, `aws_backup_vault`.
- `image_names`  
  Supports wildcards `*` and `?`.
- `marketplace_product_codes`  
  Allow specific Marketplace AMIs.
- `creation_date_condition.maximum_days_since_created`  
  “Freshness” window.
- `deprecation_time_condition.maximum_days_since_deprecated`  
  Time window after deprecation.

### Practical mid-level guidance: how to choose criteria
- Start with **provider allowlist** (your golden AMI publishing account + `amazon` if needed).
- Add **name patterns** once you have a stable convention.
- Add **age window** (like 60/90 days) after patch cadence is reliable.
- Avoid making criteria too clever early—“audit_mode first” saves careers.

---

# 4E) Instance Metadata Defaults (IMDS defaults)

### What it controls
Sets **defaults** for IMDS behavior for **new instance launches** (not a “hard enforcement” of every IMDS aspect, but it’s still a powerful baseline).

### Fields and modes

#### `http_tokens`
- **`no_preference`** → other defaults apply (AMI defaults, etc.)
- **`required`** → IMDSv2 required; IMDSv1 not allowed
- **`optional`** → IMDSv1 + IMDSv2 allowed

#### `http_endpoint`
- **`no_preference`**
- **`enabled`** → IMDS endpoint accessible
- **`disabled`** → IMDS endpoint not accessible

#### `instance_metadata_tags`
- **`no_preference`**
- **`enabled`** → tags accessible via IMDS
- **`disabled`** → tags not accessible via IMDS

#### `http_put_response_hop_limit`
- Integer **-1 to 64**  
  - `-1` means “no preference”
  - If `http_tokens` is `required`, a hop limit of **>= 2** is typically recommended in real-world setups (containers, proxies, etc.).

#### Example: IMDSv2 required, endpoint enabled, tags enabled, hop limit 4
```json
{
  "ec2_attributes": {
    "instance_metadata_defaults": {
      "http_tokens": { "@@assign": "required" },
      "http_put_response_hop_limit": { "@@assign": "4" },
      "http_endpoint": { "@@assign": "enabled" },
      "instance_metadata_tags": { "@@assign": "enabled" }
    }
  }
}
```

---

# 4F) Snapshot Block Public Access (EBS snapshots)

### What it controls
Whether EBS snapshots can be publicly shared.

### Modes (`snapshot_block_public_access.state`)
- **`unblocked`** → no restrictions
- **`block_new_sharing`** → blocks new public sharing; already-public remain public
- **`block_all_sharing`** → blocks all public sharing; already-public become private

#### Example: block all public snapshot sharing
```json
{
  "ec2_attributes": {
    "snapshot_block_public_access": {
      "state": { "@@assign": "block_all_sharing" }
    }
  }
}
```

---

## 5) Custom exception messages (developer experience)

You can define a single `exception_message` under `ec2_attributes` to return a helpful error when a noncompliant action fails.

Example:
```json
{
  "ec2_attributes": {
    "exception_message": {
      "@@assign": "AMI not approved. Use xyzzy-golden-* or request a time-bound exception via Jira."
    },
    "allowed_images_settings": {
      "state": { "@@assign": "enabled" }
    }
  }
}
```

Keep it helpful, but don’t put secrets/PII in it.

---

## 6) Limitations (what will surprise teams)

### 6.1 Service-enforced behavior
- One setting can impact multiple APIs.
- Noncompliant actions fail at the service level.
- Account admins can’t change enforced attributes inside the account.

### 6.2 API restrictions (common)
When a setting is enforced by declarative policy, accounts typically can’t use the “enable/disable/reset” style API operations to modify it (examples include serial console enable/disable, image block public access enable/disable, allowed images settings enable/disable/replace criteria).

### 6.3 “Defaults” vs “Enforcement”
Instance Metadata Defaults set defaults; they don’t retroactively rewrite existing instances, and don’t necessarily enforce every metadata behavior detail.

---

## 7) Production-ready AMI governance pattern (recommended)

### Phase 0 — Prep
- Establish golden AMI publishing pipeline (Packer, EC2 Image Builder, etc.)
- Adopt naming convention (e.g., `xyzzy-golden-<os>-<app>-<yyyy-mm-dd>`)

### Phase 1 — `audit_mode`
- Deploy Allowed AMIs in audit mode with provider allowlist + optional name pattern
- Track findings; fix app teams

### Phase 2 — `enabled` (enforcement)
- Flip to enabled after audits show low/no breakage
- Keep exception process time-bound + approved

### Phase 3 — Harden the perimeter
- Set Image Block Public Access to `block_new_sharing`
- Set Snapshot Block Public Access to `block_all_sharing` (or `block_new_sharing` if you need a gentler ramp)

---

## 8) GitOps: managing declarative policies via GitHub/GitLab

### 8.1 Repo structure (simple and effective)
```
org-governance/
  policies/
    ec2/
      allowed-amis.audit.json
      allowed-amis.enforced.json
      image-block-public-access.json
      snapshot-block-public-access.json
  scripts/
    validate-json.sh
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
stages: [validate, apply, verify]

validate:
  stage: validate
  image: amazon/aws-cli:2
  script:
    - ./scripts/validate-json.sh policies/ec2/*.json

apply:
  stage: apply
  image: amazon/aws-cli:2
  script:
    - aws organizations update-policy --policy-id "$POLICY_ID" --content file://policies/ec2/allowed-amis.audit.json

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

## 10) Quick “mid-level engineer” cheat sheet

**If your goal is “restrict AMIs safely”:**
1. Start with `allowed_images_settings.state = audit_mode`
2. Criteria: allow only your golden AMI publisher account (and optionally `amazon`)
3. Add `image_names` pattern after naming is stable
4. Add `maximum_days_since_created` after patch cadence is reliable
5. Flip to `enabled`
6. Lock down child OUs with `@@operators_allowed_for_child_policies`
7. Add Image Block Public Access = `block_new_sharing` and Snapshot Block Public Access = `block_all_sharing`

---

_End of file_
