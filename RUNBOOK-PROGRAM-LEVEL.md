# Program-Level Runbook: AWS Encryption Compliance Controls
**EBS · SQS · EFS | AWS Config + OPA Policy Governance**

---

| Field | Value |
|---|---|
| **Document Type** | Program-Level Runbook |
| **Audience** | Program Managers, Technical Leads, Security & Compliance Stakeholders |
| **Last Updated** | 2026-04-05 |
| **Status** | Active |
| **Jira Epic** | `<!-- PLACEHOLDER: e.g., CLOUD-XXXX -->` |
| **Confluence** | `<!-- PLACEHOLDER: Link to architecture decision record -->` |
| **Slack Channel** | `<!-- PLACEHOLDER: #cloud-governance or #security-compliance -->` |
| **Owners** | `<!-- PLACEHOLDER: Team / Individual -->` |

---

## 1. Executive Summary

This runbook describes the **encryption compliance program** enforced across the AWS Organization for three key storage and messaging services:

- **Amazon EBS** – Elastic Block Store volumes and snapshots
- **Amazon SQS** – Simple Queue Service queues
- **Amazon EFS** – Elastic File System file systems

Controls are applied at **two layers**:

| Layer | Tool | When | Enforcement |
|---|---|---|---|
| **Pre-deployment (IaC)** | OPA (Open Policy Agent) | During `terraform plan` in CI/CD | Advisory (warn) or Mandatory (block) |
| **Post-deployment (runtime)** | AWS Config + Conformance Packs | Continuous, on resource change | Detect and report non-compliance |

---

## 2. Business Justification

| Driver | Details |
|---|---|
| **Regulatory** | Encryption at rest and in transit is required under CIS AWS Foundations Benchmark 2.4.1, AWS Well-Architected Framework SEC08-BP02, and internal Data Classification Policy |
| **Risk Reduction** | Unencrypted storage and queues expose sensitive data to unauthorized access in the event of a breach or misconfiguration |
| **Audit Readiness** | Continuous AWS Config findings feed directly into audit reports and security dashboards |
| **Shift-Left** | OPA policies catch non-compliant IaC at PR time — before infrastructure is provisioned — reducing remediation cost |

---

## 3. Scope

### 3.1 Services Covered

| Service | Resource Type | Control Applied |
|---|---|---|
| EBS | `AWS::EC2::Volume`, `AWS::EC2::Snapshot` | Encryption at rest (Guard + OPA) |
| SQS | `AWS::SQS::Queue` | Encryption at rest — SSE-SQS or KMS (Guard) |
| EFS | `AWS::EFS::FileSystem` | Encryption at rest (Guard + OPA), KMS CMK (OPA), TLS in-transit policy (Lambda) |
| EFS Replication | `aws_efs_replication_configuration` | Destination KMS CMK (OPA Mandatory) |

### 3.2 Organizational Reach

- **AWS Config rules** deploy as **Organization Conformance Packs** — covering all member accounts in the AWS Organization.
- Accounts explicitly excluded from org packs (e.g., sandbox/test accounts with Config not enabled) are tracked in the `excluded_accounts` list in Terraform.
- **AFT Lambda rules** deploy per-account during the Account Factory for Terraform customization pipeline.

### 3.3 Regions

Rules are deployed in both:
- `us-east-2` (USE2) — primary
- `us-east-1` (USE1) — secondary

---

## 4. Control Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    DEVELOPER WORKFLOW                           │
│                                                                 │
│  Write Terraform  ──►  terraform plan  ──►  OPA Evaluation      │
│  (IaC in GitLab)        (CI Pipeline)       (Shift-Left Gate)   │
│                                               │                 │
│                                      Advisory │ Mandatory       │
│                                        warn   │  BLOCK          │
└───────────────────────────────────────────────┼─────────────────┘
                                                │
┌───────────────────────────────────────────────▼─────────────────┐
│                    AWS ORGANIZATION                             │
│                                                                 │
│  terraform apply  ──►  Resource Created  ──►  AWS Config        │
│  (Provisioned)                               Conformance Pack   │
│                                               │                 │
│                              Guard Rules      │  Lambda Rules   │
│                          (at-rest encrypt)    │  (TLS policy)   │
│                                               │                 │
│                               COMPLIANT / NON-COMPLIANT result  │
│                                               │                 │
│                          Security Hub / CloudWatch / Dashboard  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Repository Alignment

### 5.1 custom-config-rules — Organization Config Rules

**Repository:** `AWS-Terraform-Playground/custom-config-rules`
**Purpose:** Deploys Guard-based AWS Config rules as Organization Conformance Packs across all accounts.

| Path | Purpose |
|---|---|
| `environments/prd/` | Production deployment — runs from management/delegated admin account |
| `environments/dev/` | Development/testing deployment |
| `modules/conformance_pack/` | Reusable Terraform module for building and deploying conformance packs |
| `policies/ebs-is-encrypted/` | Guard policy for EBS encryption |
| `policies/sqs-is-encrypted/` | Guard policy for SQS encryption |
| `policies/efs-is-encrypted/` | Guard policy for EFS at-rest encryption |

**Key Design Decision:** Guard rules (`.guard` files) are stored separately from infrastructure code. At deploy time, Terraform reads the `.guard` file contents, inlines them into a CloudFormation YAML template, and submits it as an Organization Conformance Pack. This means:
- Guard rules are versioned by date (e.g., `ebs-is-encrypted-2026-01-09.guard`)
- Deploying a new version requires updating the `config_rule_version` variable and running `terraform apply`

### 5.2 terraform-aft-account-customizations — Lambda Rules via AFT

**Repository:** `AWS-Terraform-Playground/terraform-aft-account-customizations`
**Purpose:** Deploys Lambda-based custom Config rules to **each individual account** during AFT account vending.

| Path | Purpose |
|---|---|
| `exceptions/terraform/` | Per-account Terraform customizations applied by AFT pipeline |
| `modules/lambda/` | Reusable Lambda deployment module (IAM, S3, CloudWatch, SNS) |
| `modules/scripts/efs-tls-enforcement/` | Python Lambda function for EFS TLS policy validation |
| `modules/policy-files/efs_tls_compliance.json` | IAM policy granting Lambda permissions to evaluate EFS |

**Why Lambda instead of Guard for EFS TLS?**

Guard policies can only evaluate data present in the AWS Config configuration item. EFS resource policies (which enforce TLS / `aws:SecureTransport`) are **not included** in Config items — they require an API call (`elasticfilesystem:DescribeFileSystemPolicy`). Lambda enables complex JSON policy parsing and conditional evaluation that Guard DSL cannot express.

**AFT Deployment Flow:**
1. A new account is vended through Account Factory
2. AFT runs the `exceptions/terraform/` customization pipeline
3. Lambda function is packaged and deployed to the account
4. Account-level conformance pack is created referencing the Lambda ARN
5. AWS Config invokes the Lambda on each `AWS::EFS::FileSystem` change event

### 5.3 Terrafrom-OPA-Prasanth — Shift-Left IaC Policies

**Repository:** `AWS-Terraform-Playground/Terrafrom-OPA-Prasanth`
**Purpose:** OPA policies evaluated against `terraform plan` JSON output in GitLab CI before any `terraform apply`.

| Path | Purpose |
|---|---|
| `global-advisory-policies/` | Advisory policies — warn, never block |
| `global-manadatery-policies/` | Mandatory policies — block the pipeline |
| `global-advisory-policies/policies.hcl` | Registry of all advisory policy queries |
| `global-manadatery-policies/policies.hcl` | Registry of all mandatory policy queries |

---

## 6. What Each Control Detects

### 6.1 EBS — Elastic Block Store

| Control | Type | Finding Code | Condition Detected | Enforcement |
|---|---|---|---|---|
| AWS Config Guard | Runtime | — | `AWS::EC2::Volume` not encrypted | NON_COMPLIANT |
| AWS Config Guard | Runtime | — | `AWS::EC2::Snapshot` not encrypted | NON_COMPLIANT |
| OPA Advisory | Pre-deploy | `EBS-ENC-001` | `aws_ebs_volume` missing `encrypted = true` | WARN |
| OPA Advisory | Pre-deploy | `EBS-ENC-002` | EC2 `root_block_device` not encrypted | WARN |
| OPA Advisory | Pre-deploy | `EBS-ENC-003` | EC2 `ebs_block_device` not encrypted | WARN |

### 6.2 SQS — Simple Queue Service

| Control | Type | Finding Code | Condition Detected | Enforcement |
|---|---|---|---|---|
| AWS Config Guard | Runtime | — | Queue has neither `sqsManagedSseEnabled = true` nor a `kmsMasterKeyId` set | NON_COMPLIANT |

> **Note:** SQS is covered at runtime (Config). An OPA shift-left policy for SQS is a **planned addition** — see Section 9.

### 6.3 EFS — Elastic File System

| Control | Type | Finding Code | Condition Detected | Enforcement |
|---|---|---|---|---|
| AWS Config Guard | Runtime | — | `AWS::EFS::FileSystem` not encrypted at rest | NON_COMPLIANT |
| AWS Config Lambda | Runtime | — | EFS resource policy does not contain `Deny` with `aws:SecureTransport = false` | NON_COMPLIANT |
| OPA Advisory | Pre-deploy | `EFS-ENC-001` | `aws_efs_file_system` missing `encrypted = true` | WARN |
| OPA Advisory | Pre-deploy | `EFS-ENC-002` | EFS encrypted but no customer-managed KMS key | WARN |
| OPA Advisory | Pre-deploy | `EFS-ENC-003` | `kms_key_id` is not a valid ARN (`arn:aws:kms:...`) | WARN |
| OPA Advisory | Pre-deploy | `EFS-ENC-004` | Replication destination missing KMS key | WARN |
| OPA Mandatory | Pre-deploy | `EFS-ENC-001` | `aws_efs_file_system` not encrypted — **BLOCKS plan** | DENY |
| OPA Mandatory | Pre-deploy | `EFS-ENC-002` | EFS encrypted but no CMK — **BLOCKS plan** | DENY |
| OPA Mandatory | Pre-deploy | `EFS-ENC-003` | Invalid KMS ARN format — **BLOCKS plan** | DENY |
| OPA Mandatory | Pre-deploy | `EFS-ENC-004` | Replication destination missing CMK — **BLOCKS plan** | DENY |

---

## 7. Compliance Frameworks Referenced

| Framework | Control | Applies To |
|---|---|---|
| CIS AWS Foundations Benchmark v2.4.1 | Encryption at rest | EBS, EFS, SQS |
| AWS Well-Architected Framework SEC08-BP02 | Protect data at rest | All services |
| Internal Data Classification Policy | `<!-- PLACEHOLDER: Policy reference -->` | All services |
| SOC 2 Type II CC6.1 | Logical access and encryption | EBS, EFS |

---

## 8. Jira Alignment

### 8.1 Epic Structure (Template)

```
Epic: AWS Encryption Compliance Controls  [CLOUD-XXXX]
├── Story: EBS Encryption Org Config Rules          [CLOUD-XXXX]
│   ├── Task: Guard policy – EBS at-rest            [CLOUD-XXXX]
│   └── Task: OPA advisory policy – EBS             [CLOUD-XXXX]
├── Story: SQS Encryption Org Config Rules          [CLOUD-XXXX]
│   └── Task: Guard policy – SQS SSE/KMS            [CLOUD-XXXX]
├── Story: EFS Encryption Controls                  [CLOUD-XXXX]
│   ├── Task: Guard policy – EFS at-rest            [CLOUD-XXXX]
│   ├── Task: Lambda rule – EFS TLS in-transit      [CLOUD-XXXX]
│   ├── Task: OPA advisory policy – EFS             [CLOUD-XXXX]
│   └── Task: OPA mandatory policy – EFS            [CLOUD-XXXX]
└── Story: AFT Integration – Lambda rule deployment [CLOUD-XXXX]
```

> **Placeholder Instructions:** Replace all `[CLOUD-XXXX]` with your actual Jira ticket IDs. Align Stories to your program increment (PI) objectives.

### 8.2 Definition of Done (per Story)

- [ ] Guard/Lambda/OPA policy code reviewed and merged to `main`
- [ ] Deployed to `dev` environment and validated
- [ ] Organization Conformance Pack deployed to `prd` (management account)
- [ ] Non-compliant resources identified and tracked for remediation
- [ ] Runbook updated
- [ ] Stakeholder sign-off received

---

## 9. CCOPS — Cloud Ops Governance Platform Integration

**Repository:** `AWS-Terraform-Playground/cloud-ops-governance-platform`

CCOPS is the centralized compliance operations platform that ingests AWS Config findings, matches them against configurable policy rules stored in DynamoDB, and raises automated ServiceNow incidents for non-compliant resources.

### 9.1 How CCOPS Works

```
AWS Config (NON_COMPLIANT findings)
        │
        ▼  CSV export uploaded to S3 (raw/)
complianceIngestLambda  ──►  MySQL RDS (ingest table)
                                    │
                       EventBridge Scheduler
                                    │
                                    ▼
              complianceRulesExecutionLambda
                 reads DynamoDB (enabled rules)
                 matches ingest rows to rules
                 writes CSV to S3 (processed/)
                 writes to MySQL (actions table)
                                    │
                                    ▼
              serviceNowEventManagerLambda  ──►  ServiceNow Incident
```

### 9.2 DynamoDB Rules Table

**Table:** `ccops-policy-engine-rules`
**Source:** [cloud-ops-governance-platform/dynamo/rules.json](cloud-ops-governance-platform/dynamo/rules.json)
**Managed by:** Terraform — `dynamodb.tf` loads `rules.json` and writes each item to the table at deploy time.

Each rule has two key fields:

- **`ingest_policy`** — filter criteria (which resource types, Config rule names, annotations to match)
- **`actions_policy`** — what ServiceNow action to take when a match is found

### 9.3 Encryption Rules in CCOPS

| Rule ID | Description | Enabled | ServiceNow Impact/Urgency |
|---|---|---|---|
| `3` | EBS Encryption violations | **false** (disabled) | Impact 2 / Urgency 3 |
| `4` | SQS At-Rest Encryption violations | **false** (disabled) | Impact 2 / Urgency 3 |
| `5` | EFS At-Rest + In-Transit Encryption violations | **true** (active) | Impact 2 / Urgency 3 / Priority 4 |

> **Note:** Rules 3 and 4 (EBS and SQS) are currently `enabled: false`. They exist in the DynamoDB table and are ready to activate. Enabling them will begin generating ServiceNow incidents for non-compliant EBS volumes and SQS queues. See Section 9 of the Operations Runbook for activation steps.

### 9.4 EFS Rule — ServiceNow Incident Template (item5)

When EFS non-compliance is detected, CCOPS raises a ServiceNow incident with:

- **Short Description:** `EFS in Rest Encryption Violations for AWS Account {$ACCOUNT_NAME$} {$ACCOUNT_NUMBER$}`
- **Description:** Lists non-compliant EFS resources with a link to the KB remediation article
- **Assignment Group:** `cmdb:assignment_group`
- **Caller ID:** `ccops`
- **Impact:** 2 | **Urgency:** 3 | **Priority:** 4

The EFS rule matches on **two Config rule names** simultaneously:

- `efs-is-encrypted-conformance-pack` — at-rest encryption (Guard rule)
- `efatlsenforcement` — TLS in-transit enforcement (Lambda rule)

This means a **single CCOPS rule aggregates both encryption dimensions** into one ServiceNow incident per account.

### 9.5 Jira Alignment — CCOPS

```text
Story: CCOPS Rule Activation — EBS/SQS/EFS Encryption    [CLOUD-XXXX]
├── Task: Enable item3 (EBS) — validate, set enabled=true   [CLOUD-XXXX]
├── Task: Enable item4 (SQS) — validate, set enabled=true   [CLOUD-XXXX]
├── Task: Confirm item5 (EFS) operating correctly           [CLOUD-XXXX]
└── Task: Add exclusions for known exceptions (EBS/SQS)     [CLOUD-XXXX]
```

---

## 10. Roadmap / Backlog Items

| Item | Status | Priority | Jira |
|---|---|---|---|
| OPA advisory policy for SQS encryption (shift-left) | `<!-- PLACEHOLDER: TODO / In Progress / Done -->` | Medium | `<!-- PLACEHOLDER -->` |
| OPA mandatory policy for EBS encryption | `<!-- PLACEHOLDER -->` | High | `<!-- PLACEHOLDER -->` |
| AWS Managed Rules evaluation for EFS (`EFS_ENCRYPTED_CHECK`) | Placeholder — commented out in code | Low | `<!-- PLACEHOLDER -->` |
| Security Hub integration for Config findings | `<!-- PLACEHOLDER -->` | High | `<!-- PLACEHOLDER -->` |
| Automated remediation (SSM Automation / Lambda) | `<!-- PLACEHOLDER -->` | Medium | `<!-- PLACEHOLDER -->` |
| Additional regions beyond USE1/USE2 | `<!-- PLACEHOLDER -->` | Medium | `<!-- PLACEHOLDER -->` |

---

## 10. Contacts and Escalation

| Role | Name / Team | Contact |
|---|---|---|
| Program Owner | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Cloud Governance Lead | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Security / Compliance | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| On-Call (AWS Issues) | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |

---

## 11. Document History

| Version | Date | Author | Change |
|---|---|---|---|
| 1.0 | 2026-04-05 | `<!-- PLACEHOLDER -->` | Initial creation |
