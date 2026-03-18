# SCP: AMI Governance Design

**Policy file:** `policies/scp-ami-governance-2026-03-18.json`
**Type:** `SERVICE_CONTROL_POLICY`
**Terraform module:** `scp-ami-governance` in `environments/dev/main.tf` and `environments/prd/main.tf`
**Date:** 2026-03-18
**Replaces:** `scp-ami-guardrail-2026-01-18.json` + `scp-ami-account-restrictions-2026-03-18.json`
**Attached to:** Root OU (applies to every account in the org)

---

## Problem Statement

Prasa has three categories of AMIs:

| Category | AMI Name Pattern | Who Can Use It |
|---|---|---|
| **Golden AMIs** | `pras-al2023-*`, `pras-al2-*`, `pras-rhel8-*`, `pras-rhel9-*`, `pras-win22-*` | All accounts in the org |
| **App-specific pras AMIs** | `pras-mlal2-*`, `pras-opsdir-mlal2-*` | MarkLogic accounts only (future scope) |
| **Exception AMIs** | Vendor/marketplace AMIs (see table below) | Only the owning application's accounts |

Without controls, any account can launch any exception AMI, violating least privilege and widening the blast radius of a compromised account.

---

## Exception AMI Inventory

| Application | AMI Name Pattern | AMI Source | Allowed Accounts (dummy) |
|---|---|---|---|
| Datalake | `UpsolverPrivateVpc-*` | Upsolver (`ec2:Owner = 428641199958`) | `100000000001` dev, `100000000002` tst, `100000000003` prd |
| Transit | `gigamon-gigavue-uctv-cntlr-*` | AWS Marketplace | `200000000001` dev, `200000000002` tst, `200000000003` prd |
| Transit | `gigamon-gigavue-vseries-node-*` | AWS Marketplace | `200000000001` dev, `200000000002` tst, `200000000003` prd |
| Transit | `ftdv-*` (Cisco Firepower) | AWS Marketplace | `200000000001` dev, `200000000002` tst, `200000000003` prd |
| AgcyDshBrd | `aws-datasync-*` | Amazon\* | `300000000001` dev, `300000000002` tst, `300000000003` prd |
| TermCond | `aws-storage-gateway-FILE_S3-*` | Amazon\* | `400000000001` dev, `400000000002` tst, `400000000003` prd |
| DataSync | `aws-datasync-*` | Amazon\* | `500000000001` dev, `500000000002` tst, `500000000003` prd |
| ClaimsData | `emr-*` | Amazon\* | `600000000001` dev, `600000000002` tst, `600000000003` prd |
| Datalake | `amazon-eks-node-al2023-x86_64-standard-*` | Amazon\* | `100000000001` dev, `100000000002` tst, `100000000003` prd |

\* Amazon-owned AMIs share `ec2:Owner = "amazon"` across all services. The SCP cannot distinguish them by owner — see **SCP Limitation** below.

---

## SCP Limitation: Cannot Filter by AMI Name

AWS SCP condition keys for `ec2:RunInstances` on an image resource support:

| Condition Key | What It Matches |
|---|---|
| `ec2:Owner` | AWS account ID that owns the AMI |
| `ec2:ProductCode` | Marketplace product code(s) on the AMI |
| `ec2:ImageID` | The specific AMI ID (`ami-0abc123...`), not the name |

**AMI names cannot be used as an SCP condition.** The SCP therefore covers:
- **Upsolver AMIs** → via `ec2:Owner = "428641199958"` (unique to Upsolver)
- **Marketplace AMIs** (Gigamon, Cisco ftdv) → via `ec2:ProductCode`

Amazon-owned service AMIs (EKS node, DataSync, Storage Gateway, EMR) all share the same `ec2:Owner = "amazon"`. Restricting them to specific accounts in an SCP is not possible without affecting all Amazon AMIs org-wide. Those are handled by per-OU EC2 Declarative Policies (separate from this SCP).

---

## Policy Structure

Single SCP with 5 statements, consolidated to conserve attachment slots (AWS limit: 5 SCPs per target).

```
scp-ami-governance-2026-03-18.json
├── Statement 1: DenyNonApprovedAMIsOrgWide           (baseline guardrail)
├── Statement 2: DenyUpsolverAMIsOutsideDatalakeAccounts
├── Statement 3: DenyMarketplaceTransitAMIsOutsideTransitAccounts
├── Statement 4: DenyAMICreationAndSideload
└── Statement 5: DenyPublicAMISharing
```

---

## Statement-by-Statement Design

### Statement 1 — `DenyNonApprovedAMIsOrgWide`

Baseline guardrail. Blocks any AMI not published from Prasa ops accounts, across all accounts in the org.

**Condition logic** (keys within the same `StringNotEquals` block are ANDed):
```
DENY if (ec2:Owner NOT IN [565656565656, 666363636363])
     AND (aws:PrincipalAccount NOT IN [all 18 exception accounts])
```

| Scenario | Result |
|---|---|
| Non-exception account, ops AMI (pras-*) | Allowed — first condition is false |
| Non-exception account, any other AMI | **Denied** |
| Exception account, any AMI | Allowed from this statement — second condition is false |

**Why exception accounts are carved out:** Exception accounts use vendor/marketplace AMIs that are not published from the ops accounts. If they were not excluded, statement 1 would deny their approved exception AMIs. Statements 2 and 3 handle the cross-app blocking (e.g., a Datalake account cannot use Gigamon marketplace AMIs).

---

### Statement 2 — `DenyUpsolverAMIsOutsideDatalakeAccounts`

Restricts Upsolver AMIs (`UpsolverPrivateVpc-*`) to Datalake accounts only.

```
DENY if (ec2:Owner = "428641199958")
     AND (aws:PrincipalAccount NOT IN [100000000001, 100000000002, 100000000003])
```

Any account that is not a Datalake account — including other exception accounts like Transit — cannot launch Upsolver AMIs.

---

### Statement 3 — `DenyMarketplaceTransitAMIsOutsideTransitAccounts`

Restricts Gigamon and Cisco ftdv marketplace AMIs to Transit accounts only.

```
DENY if (ANY ec2:ProductCode IN transit_product_codes)
     AND (aws:PrincipalAccount NOT IN [200000000001, 200000000002, 200000000003])
```

Marketplace product codes in scope:

| Product Code | Product |
|---|---|
| `6dcndlpi3tu6z8ten76nuejp` | Gigamon GigaVUE-UCT Virtual |
| `a8sxy6easi2zumgtyr564z6y7` | Gigamon GigaVUE V-Series Node |
| `akjez2r6bd6o7tg3mhptif6ti` | Gigamon GigaVUE V-Series Node (amd64) |
| `7u0lnfhluv0k8cyewctn0xdx8` | Cisco Firepower Threat Defense Virtual |
| `cmudow1tph9k98mz0ctkc063w` | Additional marketplace product |

---

### Statement 4 — `DenyAMICreationAndSideload`

Prevents every account (including exception accounts) from self-publishing AMIs into the org. All AMIs must originate from the Prasa ops accounts or approved external vendors.

**Actions blocked:** `ec2:CreateImage`, `ec2:CopyImage`, `ec2:RegisterImage`, `ec2:ImportImage`
**Resource:** `*` (no exception)

---

### Statement 5 — `DenyPublicAMISharing`

Prevents any account from making AMIs publicly launchable.

**Condition:** `ec2:Add/group = "all"` blocks the `ec2:ModifyImageAttribute` call that grants public launch permission.

---

## Decision Flow

```
ec2:RunInstances called
        |
        v
[Stmt 1: DenyNonApprovedAMIsOrgWide]
  Caller in any exception account?
    YES → pass (statements 2-3 enforce cross-app restrictions)
    NO  → AMI owner in ops accounts?
            YES → ALLOWED (golden pras-* AMI)
            NO  → DENIED
        |
        v
[Stmt 2: DenyUpsolverAMIsOutsideDatalakeAccounts]
  AMI owner = 428641199958 (Upsolver)?
    NO  → pass
    YES → Caller in Datalake accounts?
            YES → ALLOWED
            NO  → DENIED
        |
        v
[Stmt 3: DenyMarketplaceTransitAMIsOutsideTransitAccounts]
  AMI has a Transit product code?
    NO  → pass
    YES → Caller in Transit accounts?
            YES → ALLOWED
            NO  → DENIED
        |
        v
  ALLOWED (ec2:RunInstances proceeds)
```

---

## Golden AMIs: No Restriction Needed

Golden AMIs (`pras-al2023-*`, `pras-al2-*`, `pras-rhel8-*`, `pras-rhel9-*`, `pras-win22-*`) are published from the ops accounts (`565656565656`, `666363636363`). Statement 1 allows all non-exception accounts to use these freely. Exception accounts can also use them — statement 1 passes for exception accounts, and no other statement blocks ops-account AMIs. No additional SCP rule is needed.

---

## Capacity

| Metric | Value |
|---|---|
| Number of statements | 5 |
| Estimated policy size | ~1,800 characters |
| AWS SCP size limit | 5,120 characters |
| Remaining capacity | ~3,300 characters (~6 additional app restriction statements) |

---

## Out of Scope

| Item | Reason |
|---|---|
| `pras-mlal2-*`, `pras-opsdir-mlal2-*` (MarkLogic) | Published from ops accounts — SCPs cannot filter by AMI name when owner is the same. Requires per-OU declarative policy. |
| Amazon-owned exception AMIs (EKS, DataSync, Storage Gateway, EMR) | Shared `ec2:Owner = "amazon"` prevents SCP-level discrimination. Handled via per-OU EC2 Declarative Policies. |
| Wiz / Cloud 1.0 Public AMIs (planned sunset) | Product code not confirmed. Add to statement 3 once known. |
