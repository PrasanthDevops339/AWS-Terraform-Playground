# AMI Governance SCP Design

**Policy file:** `policies/scp-ami-governance-2026-03-18.json`
**Terraform modules:** `scp-ami-governance` in `environments/dev/main.tf` and `environments/prd/main.tf`
**Date:** 2026-03-18
**Replaces:** `scp-ami-guardrail-2026-01-18.json` + `scp-ami-account-restrictions-2026-03-18.json`

---

## Problem Statement

Prasa has two categories of AMIs:

| Category | AMI Name Pattern | Who Can Use It |
|---|---|---|
| **Golden AMIs** | `pras-al2023-*`, `pras-al2-*`, `pras-rhel8-*`, `pras-rhel9-*`, `pras-win22-*` | All accounts in the org |
| **App-specific golden** | `pras-mlal2-*`, `pras-opsdir-mlal2-*` | MarkLogic accounts only (future scope) |
| **Exception AMIs** | Various vendor/Amazon AMIs (see table below) | Only the owning application's accounts |

Without controls, any account in the org can launch any exception AMI, violating the principle of least privilege and increasing blast radius if an account is compromised.

---

## Exception AMI Inventory

| Application | AMI Name Pattern | AMI Source | Allowed Accounts |
|---|---|---|---|
| Datalake | `amazon-eks-node-al2023-x86_64-standard-*` | Amazon (ec2:Owner = `amazon`) | `100000000001`, `100000000002`, `100000000003` |
| Datalake | `UpsolverPrivateVpc-*` | Upsolver (ec2:Owner = `428641199958`) | `100000000001`, `100000000002`, `100000000003` |
| Transit | `gigamon-gigavue-uctv-cntlr-*` | AWS Marketplace | `200000000001`, `200000000002`, `200000000003` |
| Transit | `gigamon-gigavue-vseries-node-*` | AWS Marketplace | `200000000001`, `200000000002`, `200000000003` |
| Transit | `ftdv-*` (Cisco Firepower) | AWS Marketplace | `200000000001`, `200000000002`, `200000000003` |
| AgcyDshBrd | `aws-datasync-*` | Amazon (ec2:Owner = `amazon`) | `300000000001`, `300000000002`, `300000000003` |
| TermCond | `aws-storage-gateway-FILE_S3-*` | Amazon (ec2:Owner = `amazon`) | `400000000001`, `400000000002`, `400000000003` |
| DataSync | `aws-datasync-*` | Amazon (ec2:Owner = `amazon`) | `500000000001`, `500000000002`, `500000000003` |
| ClaimsData | `emr-*` | Amazon (ec2:Owner = `amazon`) | `600000000001`, `600000000002`, `600000000003` |

---

## Why Two Enforcement Layers Are Needed

### SCP Limitation: Cannot Filter by AMI Name

AWS SCP condition keys for `ec2:RunInstances` support:
- `ec2:Owner` — the AWS account ID that owns the AMI
- `ec2:ProductCode` — marketplace product code(s) attached to the AMI
- `ec2:ImageID` — the specific AMI ID (e.g., `ami-0abc123...`), NOT the AMI name

**AMI names cannot be used as an SCP condition.** This creates a problem for Amazon-owned service AMIs because all of EKS node, DataSync, Storage Gateway, and EMR AMIs share `ec2:Owner = "amazon"`. A blanket deny on `ec2:Owner = "amazon"` would break every account, not just the wrong ones.

### Solution: SCP + Declarative Policy

| AMI Type | Restriction Method | Condition Used |
|---|---|---|
| Upsolver (`UpsolverPrivateVpc-*`) | SCP | `ec2:Owner = "428641199958"` |
| Gigamon + Cisco ftdv (marketplace) | SCP | `ec2:ProductCode` |
| Amazon service AMIs (eks, datasync, storage-gateway, emr) | EC2 Declarative Policy per OU | `image_names` criteria |

---

## SCP Design (`scp-ami-governance-2026-03-18.json`)

The policy is a single SCP with 5 statements. All exception AMI account restrictions and the baseline guardrail are consolidated into one policy to minimise SCP slot consumption (AWS limit: 5 SCPs per target).

### Statement 1: `DenyNonApprovedAMIsOrgWide`

**Purpose:** Baseline guardrail. Blocks any AMI not published from Prasa ops accounts, except when launched from a known exception account.

**Logic (AND of conditions in `StringNotEquals`):**
```
DENY if (ec2:Owner NOT IN ops_accounts) AND (aws:PrincipalAccount NOT IN all_exception_accounts)
```

- Any non-exception account that tries to use a non-ops AMI → **DENIED**
- Any non-exception account that uses an ops AMI → allowed (first condition is false)
- Any exception account → allowed from this statement (second condition is false); the app-specific statements below handle the cross-app blocking

**Why exception accounts are excluded from the baseline:** If Datalake (an exception account) is NOT excluded, statement 1 would deny their Upsolver/EKS AMIs (which are non-ops-owned), even though those AMIs are explicitly approved for Datalake. Excluding all exception accounts from statement 1 delegates the "right AMI in the right account" enforcement to statements 2 and 3.

### Statement 2: `DenyUpsolverAMIsOutsideDatalakeAccounts`

**Purpose:** Restricts Upsolver AMIs (`UpsolverPrivateVpc-*`, owner `428641199958`) to Datalake accounts only.

**Logic:**
```
DENY if (ec2:Owner = "428641199958") AND (aws:PrincipalAccount NOT IN datalake_accounts)
```

A Transit or AgcyDshBrd account cannot launch Upsolver AMIs even though they are exception accounts.

### Statement 3: `DenyMarketplaceTransitAMIsOutsideTransitAccounts`

**Purpose:** Restricts Gigamon and Cisco ftdv marketplace AMIs to Transit accounts only.

**Logic:**
```
DENY if (ANY ec2:ProductCode IN transit_product_codes) AND (aws:PrincipalAccount NOT IN transit_accounts)
```

Marketplace product codes covered:

| Code | Product |
|---|---|
| `6dcndlpi3tu6z8ten76nuejp` | Gigamon GigaVUE-UCT Virtual |
| `a8sxy6easi2zumgtyr564z6y7` | Gigamon GigaVUE V-Series Node |
| `akjez2r6bd6o7tg3mhptif6ti` | Gigamon GigaVUE V-Series Node (amd64) |
| `7u0lnfhluv0k8cyewctn0xdx8` | Cisco Firepower Threat Defense Virtual |
| `cmudow1tph9k98mz0ctkc063w` | Additional marketplace product |

### Statement 4: `DenyAMICreationAndSideload`

**Purpose:** Prevents any account (including exception accounts) from creating, copying, registering, or importing their own AMIs. All AMIs must be sourced from the Prasa ops accounts or approved vendors.

**Actions blocked:** `ec2:CreateImage`, `ec2:CopyImage`, `ec2:RegisterImage`, `ec2:ImportImage`

### Statement 5: `DenyPublicAMISharing`

**Purpose:** Prevents any account from making their AMIs publicly accessible.

**Condition:** `ec2:Add/group = "all"` — blocks the specific API call that grants public launch permission on an AMI.

---

## EC2 Declarative Policies (per app OU)

For Amazon-owned service AMIs the SCP cannot distinguish between applications. A separate `DECLARATIVE_POLICY_EC2` is attached to each application OU. This policy uses `image_names` criteria to allow only that application's exception AMIs.

| Policy File | OU | Allowed image_names |
|---|---|---|
| `declarative-policy-ec2-datalake-2026-03-18.json` | `pras_datalake_ou` | `amazon-eks-node-al2023-x86_64-standard-*`, `UpsolverPrivateVpc-*` |
| `declarative-policy-ec2-transit-2026-03-18.json` | `pras_transit_ou` | marketplace product codes (Gigamon + Cisco) |
| `declarative-policy-ec2-agcydshbrd-2026-03-18.json` | `pras_agcydshbrd_ou` | `aws-datasync-*` |
| `declarative-policy-ec2-termcond-2026-03-18.json` | `pras_termcond_ou` | `aws-storage-gateway-FILE_S3-*` |
| `declarative-policy-ec2-datasync-2026-03-18.json` | `pras_datasync_ou` | `aws-datasync-*` |
| `declarative-policy-ec2-claimsdata-2026-03-18.json` | `pras_claimsdata_ou` | `emr-*` |

### Prerequisite: Org-wide declarative policy must allow `@@append`

The existing `declarative-policy-ec2-2026-01-18.json` has:
```json
"@@operators_allowed_for_child_policies": ["@@none"]
```

This must be changed to `["@@append"]` at the `image_criteria` level so that the per-OU declarative policies can add their application-specific criteria on top of the baseline (which only allows `pras-*` AMIs from ops accounts). Without this change, the per-OU policies have no effect.

---

## AMI Decision Flow

```
ec2:RunInstances called
        |
        v
[Statement 1: DenyNonApprovedAMIsOrgWide]
  Is caller in an exception account?
    YES → skip to statement 2
    NO  → Is AMI owner in ops accounts (565656565656, 666363636363)?
            YES → ALLOWED (golden/pras-* AMI)
            NO  → DENIED
        |
        v
[Statement 2: DenyUpsolverAMIsOutsideDatalakeAccounts]
  Is AMI owner = 428641199958 (Upsolver)?
    NO  → skip
    YES → Is caller in Datalake accounts?
            YES → ALLOWED
            NO  → DENIED
        |
        v
[Statement 3: DenyMarketplaceTransitAMIsOutsideTransitAccounts]
  Does AMI have a Transit marketplace product code?
    NO  → skip
    YES → Is caller in Transit accounts?
            YES → ALLOWED
            NO  → DENIED
        |
        v
[EC2 Declarative Policy - per OU]
  Does AMI name match the OU's allowed image_names criteria?
    YES → ALLOWED
    NO  → BLOCKED (audit_mode: logged only; enabled: hard block)
```

---

## Golden AMIs: No Restriction Needed

Golden AMIs (`pras-al2023-*`, `pras-al2-*`, `pras-rhel8-*`, `pras-rhel9-*`, `pras-win22-*`) are published from the Prasa ops accounts (`565656565656`, `666363636363`). Statement 1 of this SCP allows all non-exception accounts to use AMIs from those owner accounts without restriction. Exception accounts inherit this via declarative policy criteria_1 in the org-wide policy. No additional rule is needed for golden AMIs.

---

## Out of Scope / Future Work

- **MarkLogic app-specific AMIs** (`pras-mlal2-*`, `pras-opsdir-mlal2-*`): These are published from the Prasa ops accounts. Since SCPs cannot filter by AMI name and all `pras-*` AMIs share the same owner, restricting these to MarkLogic accounts only requires a per-OU declarative policy for the MarkLogic OU (same pattern as the per-app policies above).
- **Wiz / Cloud 1.0 AMIs (planned sunset)**: Not included in this SCP. Add a marketplace product code restriction to statement 3 or a new statement once the product code is confirmed.
- **SCP character limit**: Current policy is approximately 1,800 characters. AWS limit is 5,120 characters. There is room to add more exception app restrictions as needed.
