# AWS Cloud Governance Platform — Runbook

**Services covered:** Amazon EBS · Amazon SQS · Amazon EFS
**Control layers:** OPA shift-left · AWS Config Guard rules · Config Lambda rules · CCOPS / ServiceNow incident routing

| Field | Value |
| --- | --- |
| Document Type | Single Enterprise Runbook |
| Audience | Anyone who works with or is new to this program |
| Last Updated | 2026-04-08 |
| Status | Active |
| Repository | `AWS-Terraform-Playground` |
| Jira Epic | `<!-- PLACEHOLDER: CLOUD-XXXX -->` |
| Program Owner | `<!-- PLACEHOLDER -->` |
| Slack Channel | `<!-- PLACEHOLDER -->` |

---

## Table of Contents

1. [Program Overview](#1-program-overview)
2. [How the Control Stack Works — End-to-End](#2-how-the-control-stack-works--end-to-end)
3. [Repository Map and File Ownership](#3-repository-map-and-file-ownership)
4. [custom-config-rules — Org-Level Config Rules](#4-custom-config-rules--org-level-config-rules)
5. [terraform-aft-account-customizations — Account-Level Lambda Rules](#5-terraform-aft-account-customizations--account-level-lambda-rules)
6. [Terrafrom-OPA-Prasanth — OPA Shift-Left Controls](#6-terrafrom-opa-prasanth--opa-shift-left-controls)
7. [cloud-ops-governance-platform — CCOPS Platform and ServiceNow](#7-cloud-ops-governance-platform--ccops-platform-and-servicenow)
8. [OPA Details: EBS Advisory Policy](#8-opa-details-ebs-advisory-policy)
9. [OPA Details: EFS Advisory Policy](#9-opa-details-efs-advisory-policy)
10. [OPA Details: EFS Mandatory Policy](#10-opa-details-efs-mandatory-policy)
11. [How to Fix Issues — Troubleshooting Guide](#11-how-to-fix-issues--troubleshooting-guide)
12. [Operational Procedures — Step-by-Step Changes](#12-operational-procedures--step-by-step-changes)
13. [Verification Commands](#13-verification-commands)
14. [Known Issues and Gaps](#14-known-issues-and-gaps)
15. [Program Tracking — Jira Allocation](#15-program-tracking--jira-allocation)
16. [Contacts and Approvals](#16-contacts-and-approvals)
17. [Document History](#17-document-history)

---

## 1. Program Overview

### What this program does

This program enforces security and governance compliance across AWS accounts in the organisation. It ensures:

- Storage and messaging resources are **encrypted at rest** (EBS volumes, SQS queues, EFS file systems)
- EFS connections use **TLS encryption in transit**
- When violations are detected at runtime, **ServiceNow incidents** are automatically created so teams can remediate

Enforcement happens at two stages:

**Before infrastructure is created (shift-left):**
A developer writes Terraform code. The CI pipeline runs OPA (Open Policy Agent) policies against the Terraform plan. Missing encryption settings either warn the developer (advisory) or block the merge entirely (mandatory).

**After infrastructure is created (runtime):**
AWS Config continuously evaluates resources across every account in the organisation. Non-compliant findings are picked up by CCOPS, which routes them through a data pipeline into ServiceNow.

### The four repositories

| Repository | What it owns |
| --- | --- |
| `custom-config-rules` | AWS Config Guard rules and org-level Lambda-based Config rules (EBS, SQS, EFS encryption, EFS TLS), deployed in **two regions** across all org accounts |
| `terraform-aft-account-customizations` | Account-level Config Lambda rules deployed per account via AFT (EFS TLS enforcement) |
| `Terrafrom-OPA-Prasanth` | OPA Rego policies that run in CI against Terraform plans before any resource is created |
| `cloud-ops-governance-platform` | The full CCOPS incident platform: Aurora MySQL, ECS Fargate tasks, Step Functions, S3, Lambda functions, DynamoDB rule store, ServiceNow integration |

### What we are enforcing and why

#### Encryption at rest — EBS

EBS volumes are block storage devices attached to EC2 instances. They store operating systems, databases, and application data. Unencrypted EBS data can be read by anyone with access to the underlying physical hardware.

**Required:** `encrypted = true` on every `aws_ebs_volume`, `root_block_device`, and `ebs_block_device` inside `aws_instance`.

#### Encryption at rest — SQS

SQS queues pass messages between application components. Those messages may contain sensitive data. Unencrypted queues expose message content at rest.

**Required:** Either SSE-SQS (`sqs_managed_sse_enabled = true`) or SSE-KMS (`kms_master_key_id`) on every `aws_sqs_queue`.

#### Encryption at rest and in transit — EFS

EFS shared file systems have two separate encryption requirements:

- **At rest:** The `encrypted = true` attribute on `aws_efs_file_system`. This is checked by an AWS Config Guard rule.
- **In transit (TLS):** An EFS resource policy that denies connections when `aws:SecureTransport` is `false`. AWS Config's Guard DSL cannot read EFS resource policies because they are not part of the recorded configuration item. A Lambda-based Config rule must call the EFS API to inspect the policy.

**Required:** `encrypted = true`, a customer-managed KMS key (`kms_key_id`), and an `aws_efs_file_system_policy` that denies non-TLS access for `ClientMount`, `ClientWrite`, and `ClientRootAccess` actions.


### Getting started checklist

1. Read sections 2 and 3 of this runbook (control stack and repository map).
2. Clone all four repositories.
3. Read `custom-config-rules/environments/prd/cpack_encryption.tf` and `main.tf` to see what org-level rules are deployed.
4. Read `custom-config-rules/environments/prd/lambda_efs_tls.tf` to understand the org EFS TLS Lambda.
5. Read `cloud-ops-governance-platform/dynamo/rules.json` to see the CCOPS rule definitions.
7. Browse `Terrafrom-OPA-Prasanth/global-advisory-policies/` and `global-manadatery-policies/`.
8. Check section 14 (Known Issues and Gaps) before making any changes.

---

## 2. How the Control Stack Works — End-to-End

### Control layer summary

| Layer | When | Trigger | Output |
| --- | --- | --- | --- |
| OPA shift-left | Before infra is created | `terraform plan` in CI pipeline | Advisory warn or mandatory pipeline block |
| AWS Config Guard | After infra is provisioned | Config change notification or periodic evaluation | `COMPLIANT` / `NON_COMPLIANT` finding |
| AWS Config Lambda (org-level) | After infra is provisioned | Config change notification | `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` finding |
| AWS Config Lambda (account-level) | After infra is provisioned | Config change notification | `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` finding |
| CCOPS / ServiceNow | Scheduled (monthly / weekly) | EventBridge → ECS Fargate task | ServiceNow incident created or updated |

### End-to-end flow diagram

```text
Developer writes Terraform code
        │
        ▼
CI pipeline: terraform plan → terraform show -json → opa eval
        │
        ├── advisory warn  → pipeline continues, warning logged
        └── mandatory deny → pipeline BLOCKED — merge not allowed
        │
        ▼ (code merged, terraform apply runs)
AWS resource provisioned
        │
        ├──▶ AWS Config Guard evaluates:
        │      - EBS volumes (encrypted check)
        │      - SQS queues (SSE-SQS or SSE-KMS check)
        │      - EFS file systems (Encrypted = true check)
        │
        └──▶ AWS Config Lambda evaluates:
               - EFS TLS policy via DescribeFileSystemPolicy
                 (org-level: custom-config-rules, both regions)
                 (account-level: terraform-aft-account-customizations)
        │
        ▼
AWS Config findings: COMPLIANT or NON_COMPLIANT
        │
        ▼
EventBridge cron fires ECS Fargate task (runs 1st of each month or weekly)
  └── config_aggregator.py reads enabled CCOPS rules from DynamoDB
  └── Queries AWS Config for matching NON_COMPLIANT findings
  └── Writes per-rule, per-account CSV files to S3
        │
        ▼
S3 ObjectCreated event triggers ccop-compliance-ingest Lambda
  └── Reads CSV from S3
  └── Inserts rows into Aurora MySQL (ingest table, INSERT IGNORE)
        │
        ▼
Step Functions invokes ccop-compliance-rules-execution Lambda
  └── Reads enabled rules from DynamoDB
  └── Queries MySQL ingest table for the account
  └── Groups findings by ruleId
  └── Writes processed CSVs to S3
  └── Creates action records in MySQL
        │
        ▼
ccop-servicenow-eventmanager Lambda
  └── Reads actions_policy from DynamoDB rule
  └── Fetches ServiceNow credentials from Secrets Manager
  └── Creates or updates ServiceNow incident with CSV attached
```

### Per-service coverage matrix

| Service | OPA | Guard rule (org, both regions) | Lambda rule (org, custom-config-rules) | Lambda rule (account, AFT) | CCOPS item |
| --- | --- | --- | --- | --- | --- |
| EBS at-rest | Advisory (conflict markers — see §14) | Yes — volumes only (snapshot gap) | No | No | `item3` — disabled |
| SQS at-rest | Not implemented | Yes | No | No | `item4` — disabled |
| EFS at-rest | Advisory + mandatory | Yes | No | No | `item5` — enabled |
| EFS TLS in-transit | Advisory + mandatory | No (Guard cannot read EFS policies) | Yes — USE2 + USE1 | Yes — us-east-1 only | `item5` — enabled |

---

## 3. Repository Map and File Ownership

### 3.1 `custom-config-rules`

> **Repo:** `<!-- PLACEHOLDER: link to custom-config-rules repo -->`
>
> Deploys AWS Config Guard rules and org-level Lambda rules across all accounts in both us-east-2 and us-east-1. Owns EBS, SQS, and EFS at-rest encryption rules plus the org-level EFS TLS Lambda.

### 3.2 `terraform-aft-account-customizations`

> **Repo:** `<!-- PLACEHOLDER: link to terraform-aft-account-customizations repo -->`
>
> Deploys account-level Config Lambda rules per account via AFT. Owns the EFS TLS enforcement Lambda and conformance pack (`Lambdarulesconformancepack`).

### 3.3 `Terrafrom-OPA-Prasanth`

> **Repo:** `<!-- PLACEHOLDER: link to Terrafrom-OPA-Prasanth repo -->`
>
> OPA Rego policies that run in CI against Terraform plans before any resource is created. Contains advisory (warn) policies and mandatory (block) policies.

### 3.4 `cloud-ops-governance-platform`

> **Repo:** `<!-- PLACEHOLDER: link to cloud-ops-governance-platform repo -->`
>
> The full CCOPS incident platform: Aurora MySQL, ECS Fargate scheduled tasks, Step Functions, S3, Lambda functions, DynamoDB rule store, and ServiceNow integration.

---

## 4. `custom-config-rules` — Org-Level Config Rules

### 4.1 Overview

This repository deploys AWS Config rules that apply across **every account in the AWS Organisation** in **two regions simultaneously**: `us-east-2` (USE2) and `us-east-1` (USE1). Terraform is run manually from the management or delegated admin account.

Two deployment mechanisms are used:

- **`conformance_pack` module** — deploys Guard rules bundled into an AWS Config organisation conformance pack
- **`lambda_rule` module** — deploys Python Lambda functions as organisation-level custom Config rules

### 4.2 Dual-region deployment

Every rule in this repository is deployed twice — once per region:

| Terraform module | Region | Provider alias |
| --- | --- | --- |
| `module.cpack_encryption` | us-east-2 | default |
| `module.cpack_encryption_use1` | us-east-1 | `aws.use1` |
| `module.efs_tls_enforcement` | us-east-2 | default |
| `module.efs_tls_enforcement_use1` | us-east-1 | `aws.use1` |

When verifying deployments or debugging, always check **both** regions.

### 4.3 Excluded accounts

These accounts are excluded from all org conformance packs and Lambda rules in `prd`:

| Account ID | Reason |
| --- | --- |
| `000000000000` | placeholder |
| `066777777777` | placeholder |
| `999999990618` | placeholder |
| `666666666739` | `smrrnd-tst` — AWS Config is not configured on this account and an SCP blocks it |

> **Note:** Any new sandbox account that is created must be added to this exclusion list. After updating the list, run `terraform apply` from `environments/prd/` to deploy the org Config rules with the new exclusion in effect. Remember to update both the USE2 and USE1 module blocks in `cpack_encryption.tf` and `lambda_efs_tls.tf`.

To add or remove exclusions, update the `excluded_accounts` list in both `cpack_encryption.tf` and `lambda_efs_tls.tf` under `environments/prd/`. Update both the USE2 and USE1 module blocks.

### 4.4 Conformance pack naming

The encryption conformance pack is named:

```text
<account_alias>-encryption-validation
```

Rules inside the pack are named:

```text
<account_alias>-<config_rule_name>
```

In non-prod/dev environments a random suffix is appended: `<account_alias>-<config_rule_name>-<random-id>`. This is controlled by `pre-dev-random.tf` in the dev environment.

### 4.5 EBS Guard rule

**Active Guard file:** `policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard`
**Production version in `cpack_encryption.tf`:** `2026-01-09`
**Scope in `cpack_encryption.tf`:** `AWS::EC2::Volume`, `AWS::EC2::Snapshot`

```guard
rule ebsIsEncrypted when resourceType == "AWS::EC2::Volume" {
    configuration.encrypted == true <<EBS Volumes must be encrypted>>
}
```

**Annotation on violation:** `EBS Volumes must be encrypted`
**CCOPS rule:** `item3` — currently **disabled**

> **Known gap:** The Terraform scope lists `AWS::EC2::Volume` and `AWS::EC2::Snapshot`, but the Guard file only evaluates `AWS::EC2::Volume`. EBS snapshot compliance is not actually enforced.
>
> **Old file:** `ebs-is-encrypted-2025-10-30.guard` exists but is not active in production.

### 4.6 SQS Guard rule

**Active production Guard file:** `policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard`
**Production version:** `2025-10-30`
**Dev version:** `sqs-is-encrypted-2026-01-27.guard` (different property casing, different annotation)

```guard
rule sqsIsEncrypted when resourceType == "AWS::SQS::Queue" {
    configuration.SqsManagedSseEnabled == true
        or configuration.KmsMasterKeyId exists
    <<SQS must be encrypted with SSE-SQS or SSE-KMS at the time of creation>>
}
```

**Annotation on violation:** `SQS must be encrypted with SSE-SQS or SSE-KMS at the time of creation`
**CCOPS rule:** `item4` — currently **disabled**

> **Important:** If the production version is ever upgraded to `2026-01-27`, the CCOPS `item4` annotation filter in `rules.json` must be updated in the same change, because the annotation wording differs between the two versions.

### 4.7 EFS Guard rule (at-rest only)

**Active Guard file:** `policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard`
**Production version:** `2025-10-30`
**Scope:** `AWS::EFS::FileSystem`

```guard
rule efsIsEncrypted when resourceType == "AWS::EFS::FileSystem" {
    configuration.Encrypted == true <<EFS's must be encrypted>>
}
```

**Annotation on violation:** `EFS's must be encrypted`
**CCOPS rule:** `item5` — **enabled**

This rule only checks at-rest encryption. TLS in-transit is covered by the Lambda rule (section 4.8).

### 4.8 EFS TLS Lambda rule (org-level, both regions)

**Lambda source:** `scripts/efs-tls-enforcement/lambda_function.py`
**IAM policy:** `iam/efs-tls-enforcement.json`
**Deployed by:** `environments/prd/lambda_efs_tls.tf`

This is an **organisation-level** rule applied across all accounts (except excluded ones) in both regions. It complements the Guard rule — Guard checks at-rest, this Lambda checks in-transit TLS enforcement.

> **Important: there are two EFS TLS Lambda implementations in this codebase:**
> - This one (in `custom-config-rules`) — **org-level**, both USE2 and USE1
> - The one in `terraform-aft-account-customizations` — **account-level**, us-east-1 only (via AFT)
>
> Both check the same thing. Both feed findings into CCOPS `item5`. The account-level one produces the rule name `efstlsenforcement_<account_id>`; the org-level one produces `<account_alias>-efs-tls-enforcement`.

**Why a Lambda is needed (not a Guard rule):**
EFS resource policies are not recorded in the AWS Config configuration item. A Lambda must call `elasticfilesystem:DescribeFileSystemPolicy` directly to inspect whether the policy enforces TLS.

**What the Lambda evaluates:**

1. Calls `DescribeFileSystemPolicy` to get the EFS resource policy.
2. Calls `DescribeReplicationConfigurations` to check if the file system is a replication destination.
3. Returns `NOT_APPLICABLE` for deleted resources and replication destinations.
4. Returns `NON_COMPLIANT` if:
   - The file system has no policy at all
   - The policy does not contain a `Deny` statement with `aws:SecureTransport = false` for `ClientMount`, `ClientWrite`, or `ClientRootAccess`
   - Any API call throws an exception

**Annotations on violation:**

- `EFS file system has no policy defined`
- `EFS file system has no policy - TLS enforcement not configured`
- `EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)`

**CCOPS rule:** `item5` — **enabled** (matches on substring `efs-tls-enforcement` or `efstlsenforcement`)

### 4.9 How to deploy from `custom-config-rules`

```bash
cd AWS-Terraform-Playground/custom-config-rules/environments/prd

terraform init       # first time or after module changes
terraform plan
terraform apply
```

Both the USE2 and USE1 resources are deployed in a single `terraform apply` because both providers are configured in the same workspace.

---

## 5. `terraform-aft-account-customizations` — Account-Level Lambda Rules

### 5.1 Overview

This repository deploys Config Lambda rules **per account** via the AFT (Account Factory for Terraform) account customization pipeline. AFT runs the Terraform in `exceptions/terraform/` inside each target account when account customizations execute.

One conformance pack is deployed per account:

| Conformance pack | What it contains |
| --- | --- |
| `Lambdarulesconformancepack` | EFS TLS enforcement Lambda rule |

### 5.2 EFS TLS enforcement — account-level

**Lambda source:** `modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py`
**IAM policy:** `modules/policy-files/efs_tls_compliance.json`
**Deployed by:** `exceptions/terraform/lambda-rules-enforcement.tf`
**Conformance pack:** `Lambdarulesconformancepack`
**Default region:** `us-east-1` (from `variables.tf` default for `var.region`)

**Config rule name produced:** `efstlsenforcement_<account_id>`

**Lambda permissions (from `efs_tls_compliance.json`):**

- `config:PutEvaluations`
- `elasticfilesystem:DescribeFileSystemPolicy`
- `elasticfilesystem:DescribeFileSystems`
- `elasticfilesystem:DescribeReplicationConfigurations`
- CloudWatch Logs permissions

Same compliance logic and same annotation messages as the org-level Lambda in `custom-config-rules`.

> To deploy to multiple regions, the `var.region` variable must be set per deployment. This is not automatic.

### 5.3 How to deploy via AFT

You do not run `terraform apply` manually for this repository. AFT runs it automatically per account when customizations execute.

**To plan locally (without applying):**

```bash
cd AWS-Terraform-Playground/terraform-aft-account-customizations/exceptions/terraform

# Requires valid AWS credentials for the target account
terraform init
terraform plan
```

**After AFT runs, verify in the target account:**

```bash
# EFS TLS conformance pack
aws configservice describe-conformance-packs \
  --query 'ConformancePackDetails[?ConformancePackName==`Lambdarulesconformancepack`]'

# Lambda functions
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `efs-tls`)].FunctionName'
```

---

## 6. `Terrafrom-OPA-Prasanth` — OPA Shift-Left Controls

### 6.1 How OPA fits into CI

OPA runs in the CI pipeline **before** `terraform apply`. The pipeline:

1. Generates a Terraform plan: `terraform plan -out=tfplan.binary`
2. Converts to JSON: `terraform show -json tfplan.binary > tfplan.json`
3. Runs advisory checks: non-empty `warn` set → warning logged, pipeline continues
4. Runs mandatory checks: non-empty `deny` set → pipeline **fails**, merge blocked

OPA evaluates `input.resource_changes` in the plan JSON — specifically `change.actions` (`create` / `update`) and `change.after` (the proposed state).

### 6.2 Policy registry

Each folder has a `policies.hcl` file that registers which OPA queries run in CI. A `.rego` file that exists in the folder but is **not registered in `policies.hcl`** is never evaluated. If you add a new policy file, you must register it.

### 6.3 Enforcement levels

| Folder | Level | Effect on pipeline |
| --- | --- | --- |
| `global-advisory-policies/` | Advisory | Warns but does not block — merge is allowed |
| `global-manadatery-policies/` | Mandatory | Non-empty `deny` result **blocks the merge** |

### 6.4 Implemented policies

| File | Package | Level | What it checks |
| --- | --- | --- | --- |
| `aws_ebs_001_advise_encryption.rego` | `aws_ebs_001_advise_encryption` | Advisory | EBS volumes, EC2 root block devices, EC2 attached EBS devices — must have `encrypted = true` |
| `aws_efs_001_advise_encryption.rego` | `aws_efs_001_advise_encryption` | Advisory | EFS `encrypted = true`, customer-managed KMS key, valid KMS ARN, replication destinations |
| `aws_efs_001_mandatory_encryption.rego` | `aws_efs_001_mandatory_encryption` | Mandatory | Same checks as EFS advisory but blocks the pipeline |

### 6.5 Registry gaps

| Registry entry | Problem |
| --- | --- |
| `aws_sqs_001_advise_module_usage.warn` in `policies.hcl` | No corresponding `.rego` file — OPA will error |
| `aws_efs_001_advise_module_usage.rego` | File exists but contains only `package advisory` — no actual policy logic |

### 6.6 Running OPA locally

> **Full guide:** `<!-- PLACEHOLDER: link to OPA local testing doc -->`

---

## 7. `cloud-ops-governance-platform` — CCOPS Platform and ServiceNow

> **Full CCOPS architecture and workflow guide:** `<!-- PLACEHOLDER: link to CCOPS how-it-works doc -->`

### 7.1 What this platform is

CCOPS is the bridge between AWS Config findings and ServiceNow. It is an event-driven data pipeline:

- Reads which rules to enforce from DynamoDB
- Periodically aggregates non-compliant Config findings into S3 CSVs
- Processes those CSVs through Lambda functions into MySQL
- Creates or updates ServiceNow incidents

### 7.2 Infrastructure components

| Component | File | Purpose |
| --- | --- | --- |
| Aurora MySQL | `mysqlrds.tf` | Stores all ingest rows and action records; all Lambdas connect to this |
| DynamoDB | `dynamodb.tf` | Stores CCOPS rule definitions in table `ccops-policy-engine-rules` |
| ECS Fargate cluster | `ecs-cluster.tf` | Runs the compliance aggregation tasks on a schedule |
| ECS task definitions | `task-definition.tf` | Defines ingest task, EC2 inventory task |
| EventBridge rules | `scheduler.tf` | Cron schedules that trigger ECS Fargate tasks |
| Step Functions | `stepfunction.tf` | Orchestrates the Lambda chain after S3 ingest |
| S3 | `s3.tf` | Stores per-rule per-account CSV files and Lambda deployment packages |
| S3 trigger | `s3triggeringest.tf` | ObjectCreated event fires `ccop-compliance-ingest` Lambda |
| SNS | `sns.tf` | Alert notifications |
| KMS | `kms.tf` | Encryption key for S3, RDS, and DynamoDB |
| Secrets Manager | `secrets.tf` | ServiceNow API credentials |
| Security groups | `securitygroups.tf` | VPC security group controlling Lambda → MySQL access |
| Lambda layers | `layers.tf` | Shared dependencies: `pymysql`, `pandas`, `pysnow`, OTEL, Splunk |
| IAM | `iam.tf` | Roles for all Lambdas and ECS tasks |

All Lambda functions and ECS tasks run inside a **VPC** using application subnets with the `lambda_database_access_security_group` security group.

### 7.3 Lambda functions

| Lambda name | Script | Purpose |
| --- | --- | --- |
| `ccop-servicenow-eventmanager` | `servicenow_eventmanager.py` | Reads action records from MySQL, creates/updates ServiceNow incidents via `pysnow` |
| `ccop-compliance-ingest` | `compliance_ingest.py` | Triggered by S3 event; reads CSV, inserts rows into MySQL `ingest` table using `INSERT IGNORE` |
| `ccop-compliance-rules-execution` | `complianceRulesExecution.py` | Scans DynamoDB for enabled rules, queries MySQL, groups findings by ruleId, writes processed CSVs, inserts action records |
| `ccop-database-bootstrap` | `database_bootstrap.py` | One-time schema setup; run once when setting up a new environment |

**Lambda layers:**

- `advanced_python_wrapper_mysql` — IAM-authenticated MySQL connectivity
- `pandas_numpy_xlsxwriter` — CSV/Excel generation for ServiceNow attachments
- `pysnow` — ServiceNow REST API client
- `otel` — OpenTelemetry instrumentation
- `splunk` — Splunk observability layer

### 7.4 ECS Fargate schedules

| EventBridge rule | Cron | Schedule | What runs |
| --- | --- | --- | --- |
| `scheduled-ecs-event-rule` | `cron(0 8 1 * ? *)` | 1st of every month, 08:00 UTC | Main ingest task — queries Config findings for all enabled CCOPS rules |
| `scheduled-ec2-event-rule` | `cron(0 10 1 * ? *)` | 1st of every month, 10:00 UTC | EC2 inventory task |

> The main ingest task runs **monthly**. A violation created after the 1st of the month will not generate a ServiceNow incident until the next scheduled run — up to 31 days later. For urgent cases, the ECS task can be triggered manually (see section 13).

### 7.5 Observability

All Lambdas are instrumented with OpenTelemetry and Splunk:

```text
AWS_LAMBDA_EXEC_WRAPPER     = "/opt/otel-instrument"
OTEL_SERVICE_NAME           = "<Lambda name>"
OTEL_PYTHON_LOG_CORRELATION = "true"
SPLUNK_REALM                = "us0"
```

Logs are written to the `/application_logs` CloudWatch log group in `us-east-2`.

### 7.6 MySQL `ingest` table schema

The `ingest` table stores one row per Config finding per run:

| Column | Description |
| --- | --- |
| `source` | Always `"aws_config"` |
| `id` | CCOPS rule ID (matches DynamoDB `id` field) |
| `resourceId` | AWS resource ID |
| `resourceType` | e.g. `"AWS::EFS::FileSystem"` |
| `resourceName` | Resource name |
| `complianceType` | `"NON_COMPLIANT"` |
| `configRuleName` | e.g. `"mycompany-efs-is-encrypted"` |
| `description` | The annotation/violation message from Config |
| `accountId` | AWS account ID |
| `accountName` | AWS account name |
| `awsRegion` | Region of the resource |
| `cloudVersion` | Currently `"2.0"` |

Inserts use `INSERT IGNORE` so duplicate findings from repeated runs are silently discarded.

### 7.7 ServiceNow integration

| Setting | Value |
| --- | --- |
| Instance name | `prasn${var.environment}` — e.g. `prasndev`, `prasnprod` |
| Credentials | AWS Secrets Manager |
| Python client | `pysnow` library |
| Default assignment group | `Cloud Enblmnt-Cloud Operations` |
| Ticket category | `Application -> Other Issue` |
| KB article URL | `https://prasnprod.service-now.com/kb_view.do?sys_kb_id=d409b489c3ea16d83354392f0501311f` |

### 7.8 `actions_policy` field structure

This field in `rules.json` controls how the ServiceNow incident is created. For `item5` (EFS) it is:

```json
{
  "Action": {
    "Target": "servicenow",
    "Type": "incident",
    "CallerId": "ccops",
    "AssignmentGroup": "cmdb:assignment_group",
    "ConfigurationItem": "aws_account",
    "Impact": 2,
    "Urgency": 3,
    "Priority": 4,
    "ShortDescription": "EFS Encryption Violations for AWS Account {$ACCOUNT_NAME$} {$ACCOUNT_NUMBER$}",
    "Description": "EFS encryption violations have been detected in AWS account {$ACCOUNT_NAME$}. Please refer to the attached CSV file for a detailed list of non-compliant resources. To remediate, ensure that all listed EFS resources are brought into compliance by enabling encryption in accordance with security standards. Follow the step-by-step remediation guidance outlined in the following knowledge base article: https://sampleurl.com/23rtw4f/3rfwef"
  }
}
```

`{$ACCOUNT_NAME$}` and `{$ACCOUNT_NUMBER$}` are substituted at runtime by the ServiceNow Event Manager Lambda.

Items 3–4 use a simpler `actions_policy` with no `ShortDescription` / `Description` / `Priority` fields.

### 7.9 All CCOPS rules in `rules.json`

| Item | Service area | Enabled | `Rules` filter | `Annotations` filter |
| --- | --- | --- | --- | --- |
| `item3` / `id=3` | EBS encryption | **disabled** | `ebs-is-encrypted` | `EBS Volumes must be encrypted` |
| `item4` / `id=4` | SQS encryption | **disabled** | `sqs-is-encrypted` | `SQS must be encrypted` |
| `item5` / `id=5` | EFS encryption (at-rest + TLS) | **enabled** | `efs-is-encrypted`, `efstlsenforcement` | `EFS's must be encrypted`, `EFS file system has no policy`, `EFS policy does not enforce TLS` |

### 7.10 Why rules use substring matching (not full rule names)

Config rule names are generated at deployment time and include account-specific prefixes or suffixes:

- Guard rules in org conformance packs: `<account_alias>-efs-is-encrypted`
- AFT Lambda rules: `efstlsenforcement_<account_id>`

Storing the full name in CCOPS breaks whenever the account alias changes or a new account is onboarded. Storing a **stable substring** (e.g. `efs-is-encrypted`, `efstlsenforcement`) matches regardless. The same applies to `Annotations` — store the stable core phrase, not the full sentence.

### 7.11 `Exclusions` field in `ingest_policy`

`item5` has an `Exclusions` array in its `ingest_policy`. This allows specific accounts, regions, resource types, resource IDs, or ARNs to be excluded from CCOPS processing even if AWS Config marks them non-compliant. All exclusion arrays are currently empty:

```json
"Exclusions": [{"Accounts": [], "Regions": [], "ResourceTypes": [], "ResourceIds": [], "ARNs": []}]
```

To exclude a specific account from EFS incident generation without excluding it from Config evaluation, add the account ID to the `Accounts` array and re-apply the CCOPS Terraform.

---

## 8. OPA Details: EBS Advisory Policy

### 8.1 What it checks

**File:** `global-advisory-policies/aws_ebs_001_advise_encryption.rego`
**Level:** Advisory — warns, never blocks

| ID | Resource | Fires when |
| --- | --- | --- |
| `EBS-ENC-001` | `aws_ebs_volume` | `encrypted` is not `true` |
| `EBS-ENC-002` | `aws_instance` | `root_block_device.encrypted` is not `true` |
| `EBS-ENC-003` | `aws_instance` | `ebs_block_device.encrypted` is not `true` |

### 8.2 Warning message format

```text
ADVISORY [EBS-ENC-001]: Standalone EBS volume 'my_volume' is not encrypted.
Set `encrypted = true` on aws_ebs_volume. [Address: aws_ebs_volume.my_volume]

ADVISORY [EBS-ENC-002]: EC2 instance 'web_server' has an unencrypted root block device.
Set `root_block_device.encrypted = true`. [Address: aws_instance.web_server]

ADVISORY [EBS-ENC-003]: EC2 instance 'web_server' has an unencrypted attached EBS block device.
Set `ebs_block_device.encrypted = true`. [Address: aws_instance.web_server]
```

### 8.3 Terraform fixes

**EBS-ENC-001:**

```hcl
resource "aws_ebs_volume" "data" {
  availability_zone = "us-east-1a"
  size              = 100
  encrypted         = true
  kms_key_id        = var.kms_key_arn
}
```

**EBS-ENC-002:**

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0123456789abcdef0"
  instance_type = "t3.micro"
  root_block_device {
    volume_size = 20
    encrypted   = true
    kms_key_id  = var.kms_key_arn
  }
}
```

**EBS-ENC-003:**

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0123456789abcdef0"
  instance_type = "t3.micro"
  ebs_block_device {
    device_name = "/dev/sdb"
    volume_size = 50
    encrypted   = true
    kms_key_id  = var.kms_key_arn
  }
}
```

---

## 9. OPA Details: EFS Advisory Policy

### 9.1 What it checks

**File:** `global-advisory-policies/aws_efs_001_advise_encryption.rego`
**Level:** Advisory — warns, never blocks

| ID | Resource | Fires when |
| --- | --- | --- |
| `EFS-ENC-001` | `aws_efs_file_system` | `encrypted` is not `true` |
| `EFS-ENC-002` | `aws_efs_file_system` | `encrypted = true` but `kms_key_id` is missing or empty |
| `EFS-ENC-003` | `aws_efs_file_system` | `kms_key_id` does not start with `arn:aws:kms:` |
| `EFS-ENC-004` | `aws_efs_replication_configuration` | A destination block has no `kms_key_id` |

### 9.2 Warning message format

```text
ADVISORY [EFS-ENC-001]: EFS file system 'shared_storage' does not have encryption enabled.
Set `encrypted = true` on aws_efs_file_system. [Address: aws_efs_file_system.shared_storage]

ADVISORY [EFS-ENC-002]: EFS file system 'shared_storage' is encrypted but missing a
customer-managed KMS key. Set `kms_key_id` to a CMK ARN.
[Address: aws_efs_file_system.shared_storage]

ADVISORY [EFS-ENC-003]: EFS file system 'shared_storage' has kms_key_id 'alias/my-key'
which is not a valid KMS ARN. Expected format: arn:aws:kms:<region>:<account-id>:key/<key-id>.

ADVISORY [EFS-ENC-004]: EFS replication configuration 'replication' has a destination
without a customer-managed KMS key. Set `kms_key_id` on every replication destination block.
```

### 9.3 Terraform fixes

**EFS-ENC-001 and EFS-ENC-002:**

```hcl
resource "aws_efs_file_system" "shared" {
  creation_token = "my-efs"
  encrypted      = true
  kms_key_id     = "arn:aws:kms:us-east-1:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

**EFS-ENC-003 — use a full KMS ARN:**

```hcl
# WRONG — alias is rejected
kms_key_id = "alias/my-key"

# WRONG — bare key ID is rejected
kms_key_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# CORRECT
kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**EFS-ENC-004:**

```hcl
resource "aws_efs_replication_configuration" "dr" {
  source_file_system_id = aws_efs_file_system.shared.id
  destination {
    region     = "us-west-2"
    kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}
```

---

## 10. OPA Details: EFS Mandatory Policy

### 10.1 What it checks

**File:** `global-manadatery-policies/aws_efs_001_mandatory_encryption.rego`
**Level:** Mandatory — non-empty `deny` **blocks the pipeline**

Enforces the same four rules as the advisory policy:

| ID | Resource | Blocks merge when |
| --- | --- | --- |
| `EFS-ENC-001` | `aws_efs_file_system` | `encrypted` is not `true` |
| `EFS-ENC-002` | `aws_efs_file_system` | Encrypted but `kms_key_id` is missing or empty |
| `EFS-ENC-003` | `aws_efs_file_system` | `kms_key_id` is not a valid `arn:aws:kms:` ARN |
| `EFS-ENC-004` | `aws_efs_replication_configuration` | Destination block missing `kms_key_id` |

### 10.2 Deny message format

```text
DENY [EFS-ENC-001]: EFS 'shared_storage' does not have encryption enabled.
Set `encrypted = true` in the aws_efs_file_system resource.
[Address: aws_efs_file_system.shared_storage]

DENY [EFS-ENC-002]: EFS 'shared_storage' is encrypted but missing a customer-managed KMS key.
Set `kms_key_id = var.kms_key_arn` pointing to a customer-managed CMK.

DENY [EFS-ENC-003]: EFS 'shared_storage' has kms_key_id 'alias/my-key' which is not a valid KMS ARN.
Expected format: arn:aws:kms:<region>:<account-id>:key/<key-id>.

DENY [EFS-ENC-004]: EFS replication configuration 'replication' has a destination without a
customer-managed KMS key. Set `kms_key_id` on every replication destination block.
```

The merge stays blocked until the code is fixed and the pipeline re-runs. Apply the same Terraform fixes as section 9.3.

---

## 11. How to Fix Issues — Troubleshooting Guide

### 11.1 OPA pipeline — EBS advisory warning (EBS-ENC-001 / 002 / 003)

These are **advisory only** — they do not block the merge. Fix them to prevent runtime Config violations later.

**Action:** Add `encrypted = true` and `kms_key_id = var.kms_key_arn` to the flagged resource. See section 8.3 for full code examples.

---

### 11.2 OPA pipeline blocked — EFS mandatory deny (EFS-ENC-001 / 002 / 003 / 004)

The merge is **blocked**. Fix the Terraform code, push a new commit, and re-run the pipeline.

Common mistakes:

- Forgot `encrypted = true` on `aws_efs_file_system`
- `kms_key_id` is set to an alias (`alias/my-key`) instead of a full ARN
- Added `aws_efs_replication_configuration` but no `kms_key_id` on the destination block

See section 9.3 for fixes.

---

### 11.3 AWS Config — EBS volume NON_COMPLIANT

**Symptom:** `<account-alias>-ebs-is-encrypted` rule shows `NON_COMPLIANT` for an EBS volume.

> EBS encryption **cannot be enabled on an existing volume**. You must snapshot, copy with encryption, and replace.

**Remediation steps:**

```bash
# 1. Create a snapshot of the unencrypted volume
aws ec2 create-snapshot \
  --volume-id vol-xxxxxxxxxxxxxxxxx \
  --description "pre-encryption snapshot"

# 2. Copy the snapshot with encryption enabled
aws ec2 copy-snapshot \
  --source-snapshot-id snap-xxxxxxxxxxxxxxxxx \
  --source-region us-east-1 \
  --destination-region us-east-1 \
  --encrypted \
  --kms-key-id arn:aws:kms:us-east-1:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 3. Create a new encrypted volume from the copied snapshot
aws ec2 create-volume \
  --snapshot-id snap-yyyyyyyyyyyyyyyyy \
  --availability-zone us-east-1a \
  --encrypted \
  --kms-key-id arn:aws:kms:us-east-1:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 4. Detach old volume, attach new encrypted volume, verify application
# 5. Delete the old unencrypted volume
```

Update the Terraform resource to reflect `encrypted = true` so future plans do not flag it again.

---

### 11.4 AWS Config — SQS queue NON_COMPLIANT

**Symptom:** `<account-alias>-sqs-is-encrypted` shows `NON_COMPLIANT`.

SQS encryption **can be enabled on an existing queue** — no replacement needed.

**Fix (SSE-SQS):**

```hcl
resource "aws_sqs_queue" "my_queue" {
  name                    = "my-queue"
  sqs_managed_sse_enabled = true
}
```

**Fix (SSE-KMS with customer-managed key):**

```hcl
resource "aws_sqs_queue" "my_queue" {
  name                              = "my-queue"
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300
}
```

Apply the change. AWS Config will re-evaluate the queue after the next change notification or on its next periodic cycle.

---

### 11.5 AWS Config — EFS file system NON_COMPLIANT (at-rest Guard rule)

**Symptom:** `<account-alias>-efs-is-encrypted` shows `NON_COMPLIANT`.

> EFS at-rest encryption **cannot be enabled after a file system is created**. You must create a new file system and migrate the data.

**Remediation steps:**

1. Create a new encrypted EFS file system in Terraform:
   ```hcl
   resource "aws_efs_file_system" "shared_encrypted" {
     creation_token = "my-efs-v2"
     encrypted      = true
     kms_key_id     = var.kms_key_arn
   }
   ```
2. Mount both old and new file systems on a migration EC2 instance.
3. Copy data using `rsync`:
   ```bash
   rsync -avz /mnt/old-efs/ /mnt/new-efs/
   ```
4. Update all applications and mount targets to point to the new file system ID.
5. Verify applications work correctly.
6. Remove all clients from the old file system.
7. Delete the old unencrypted file system via Terraform.

---

### 11.6 AWS Config — EFS file system NON_COMPLIANT (TLS Lambda rule)

**Symptom:** `efstlsenforcement_<account_id>` or `<account-alias>-efs-tls-enforcement` shows `NON_COMPLIANT` with one of:

- `EFS file system has no policy defined`
- `EFS file system has no policy - TLS enforcement not configured`
- `EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)`

**Fix:** Add an `aws_efs_file_system_policy` that denies non-TLS access:

```hcl
resource "aws_efs_file_system_policy" "tls_enforcement" {
  file_system_id = aws_efs_file_system.shared.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnforceTLS"
      Effect    = "Deny"
      Principal = { AWS = "*" }
      Action    = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      Resource  = "*"
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
```

After applying, trigger a manual re-evaluation:

```bash
aws configservice start-config-rules-evaluation \
  --config-rule-names "efstlsenforcement_<account_id>"
```

---

### 11.7 CCOPS is not generating a ServiceNow incident for an EFS finding

Work through this checklist in order:

1. **Is `item5` enabled in DynamoDB?**
   ```bash
   aws dynamodb get-item \
     --table-name ccops-policy-engine-rules \
     --key '{"source":{"S":"aws_config"},"id":{"N":"5"}}'
   ```
   Check that `"enabled": {"BOOL": true}` is present.

2. **Does the Config rule name contain the substring `efs-is-encrypted` or `efstlsenforcement`?**

   Check the actual rule name in the account — it must contain one of those substrings.

3. **Does the Config annotation contain one of the expected substrings?**

   Valid substrings: `EFS's must be encrypted`, `EFS file system has no policy`, `EFS policy does not enforce TLS`.

4. **Has the ECS Fargate ingest task run since the finding was created?**

   The task runs on the 1st of each month. To trigger it manually, see section 13.

5. **Check CloudWatch logs** for `ccop-compliance-ingest` and `ccop-compliance-rules-execution` in `us-east-2`.

6. **Check the ServiceNow Event Manager Lambda logs** for authentication or API errors.

---

### 11.9 Trigger a manual AWS Config re-evaluation

```bash
# EBS
aws configservice start-config-rules-evaluation \
  --config-rule-names "<account-alias>-ebs-is-encrypted"

# SQS
aws configservice start-config-rules-evaluation \
  --config-rule-names "<account-alias>-sqs-is-encrypted"

# EFS at-rest
aws configservice start-config-rules-evaluation \
  --config-rule-names "<account-alias>-efs-is-encrypted"

# EFS TLS — org-level Lambda rule
aws configservice start-config-rules-evaluation \
  --config-rule-names "<account-alias>-efs-tls-enforcement"

# EFS TLS — account-level AFT Lambda rule
aws configservice start-config-rules-evaluation \
  --config-rule-names "efstlsenforcement_<account_id>"
```

---

---

## 12. Operational Procedures — Step-by-Step Changes

### 12.1 Update a Guard rule version in production

1. Create the new versioned Guard file:
   ```
   custom-config-rules/policies/<rule-name>/<rule-name>-YYYY-MM-DD.guard
   ```

2. Update `config_rule_version` in `environments/prd/cpack_encryption.tf`. **Update both the USE2 and USE1 module blocks.**

3. If the annotation wording changed, note it — update `cloud-ops-governance-platform/dynamo/rules.json` in the same change window.

4. Plan and apply:
   ```bash
   cd AWS-Terraform-Playground/custom-config-rules/environments/prd
   terraform init
   terraform plan
   terraform apply
   ```

5. Verify both regions:
   ```bash
   # USE2
   aws configservice get-organization-conformance-pack-detailed-status \
     --organization-conformance-pack-name "<account-alias>-encryption-validation"

   # USE1
   aws configservice get-organization-conformance-pack-detailed-status \
     --organization-conformance-pack-name "<account-alias>-encryption-validation" \
     --region us-east-1
   ```

---

### 12.2 Update the org-level EFS TLS Lambda code

1. Edit `custom-config-rules/scripts/efs-tls-enforcement/lambda_function.py`.
2. Plan and apply from `environments/prd` — both USE2 and USE1 modules redeploy automatically.
3. Verify:
   ```bash
   aws lambda list-functions \
     --query 'Functions[?contains(FunctionName, `efs-tls-enforcement`)].FunctionName'
   ```

---

### 12.3 Update the account-level EFS TLS Lambda (AFT)

1. Edit `terraform-aft-account-customizations/modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py`.
2. Merge the change — AFT runs `terraform apply` per account automatically.
3. Verify the conformance pack is still active in target accounts:
   ```bash
   aws configservice describe-conformance-packs \
     --query 'ConformancePackDetails[?ConformancePackName==`Lambdarulesconformancepack`]'
   ```

---

### 12.4 Update an OPA Rego policy

1. Edit the `.rego` file.
2. Update `policies.hcl` if adding a new query or changing enforcement level.
3. Run tests:
   ```bash
   opa test Terrafrom-OPA-Prasanth/global-advisory-policies/ -v
   opa test Terrafrom-OPA-Prasanth/global-manadatery-policies/ -v
   ```
4. Evaluate against a sample plan:
   ```bash
   opa eval \
     --data Terrafrom-OPA-Prasanth/global-advisory-policies/ \
     --input path/to/tfplan.json \
     "data.terraform.policies.aws_efs_001_advise_encryption.warn"
   ```
5. Merge and verify CI.

---

### 12.5 Update a CCOPS rule in `rules.json`

1. Edit `cloud-ops-governance-platform/dynamo/rules.json`.
   - Use stable substrings in `Rules` and `Annotations`.
   - Before enabling a disabled rule, verify the substring values match actual Config finding names and annotations.
2. Apply:
   ```bash
   cd AWS-Terraform-Playground/cloud-ops-governance-platform
   terraform init
   terraform plan
   terraform apply
   ```
3. Validate the DynamoDB item:
   ```bash
   aws dynamodb get-item \
     --table-name ccops-policy-engine-rules \
     --key '{"source":{"S":"aws_config"},"id":{"N":"5"}}'
   ```

---

### 12.6 Add an account to the exclusion list

1. Add the account ID with a comment to `excluded_accounts` in both:
   - `environments/prd/cpack_encryption.tf` — both USE2 and USE1 blocks
   - `environments/prd/lambda_efs_tls.tf` — both USE2 and USE1 blocks

2. Apply from `environments/prd`.

---

## 13. Verification Commands

### Org conformance pack status

```bash
# USE2 (us-east-2)
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name "<account-alias>-encryption-validation"

# USE1 (us-east-1)
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name "<account-alias>-encryption-validation" \
  --region us-east-1
```

### Config compliance checks (run in target account)

```bash
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "<account-alias>-ebs-is-encrypted" \
  --compliance-types NON_COMPLIANT

aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "<account-alias>-sqs-is-encrypted" \
  --compliance-types NON_COMPLIANT

aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "<account-alias>-efs-is-encrypted" \
  --compliance-types NON_COMPLIANT

aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "<account-alias>-efs-tls-enforcement" \
  --compliance-types NON_COMPLIANT

aws configservice get-compliance-details-by-config-rule \
  --config-rule-name "efstlsenforcement_<account_id>" \
  --compliance-types NON_COMPLIANT
```

### AFT conformance packs (run in target account)

```bash
aws configservice describe-conformance-packs

aws configservice describe-conformance-packs \
  --query 'ConformancePackDetails[?ConformancePackName==`Lambdarulesconformancepack`]'

```

### Lambda functions

```bash
# Org-level (custom-config-rules)
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `efs-tls-enforcement`)].FunctionName'

# Account-level (AFT)
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `backup-tags`) || contains(FunctionName, `patching-tags`) || contains(FunctionName, `finops-tags`) || contains(FunctionName, `platform-tags`)].FunctionName'
```

### CCOPS DynamoDB

```bash
# All enabled rules
aws dynamodb scan \
  --table-name ccops-policy-engine-rules \
  --filter-expression "#en = :val" \
  --expression-attribute-names '{"#en":"enabled"}' \
  --expression-attribute-values '{":val":{"BOOL":true}}'

# Individual items
aws dynamodb get-item --table-name ccops-policy-engine-rules \
  --key '{"source":{"S":"aws_config"},"id":{"N":"1"}}'
aws dynamodb get-item --table-name ccops-policy-engine-rules \
  --key '{"source":{"S":"aws_config"},"id":{"N":"3"}}'
aws dynamodb get-item --table-name ccops-policy-engine-rules \
  --key '{"source":{"S":"aws_config"},"id":{"N":"5"}}'
```

### OPA health check

```bash
grep -rn '<<<<<<<\|=======\|>>>>>>>' \
  AWS-Terraform-Playground/Terrafrom-OPA-Prasanth/
```

### Trigger CCOPS ECS Fargate task manually

```bash
aws ecs run-task \
  --cluster <ecs-cluster-arn> \
  --task-definition <ingest-task-definition-arn> \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-id>],securityGroups=[<sg-id>],assignPublicIp=ENABLED}"
```

---

## 14. Known Issues and Gaps

| Area | Current State | Impact | Recommended Action |
| --- | --- | --- | --- |
| EBS advisory Rego — merge conflict | `aws_ebs_001_advise_encryption.rego` has unresolved Git conflict markers | File fails to parse; EBS advisory CI output is unreliable | Resolve conflict, keep HEAD version, run `opa test` to confirm |
| EBS Guard — snapshot coverage gap | Guard file only evaluates `AWS::EC2::Volume` despite scope including `AWS::EC2::Snapshot` | EBS snapshots are not actually checked at runtime | Add snapshot rule to the Guard file or remove snapshot from scope |
| SQS shift-left — no OPA policy | No SQS encryption `.rego` file exists | SQS encryption is runtime-only; no CI pre-check | Decide whether to implement; if yes, create the file and register it |
| SQS module-usage registry orphan | `policies.hcl` references `aws_sqs_001_advise_module_usage.warn` but no file exists | OPA will error when loading the advisory policy folder | Create the file or remove the registry entry |
| EFS module-usage policy — placeholder | `aws_efs_001_advise_module_usage.rego` contains only `package advisory` | Advisory is listed in registry but does nothing | Implement real logic or remove |
| SQS Guard: prod vs dev versions | Prod uses `2025-10-30`, dev uses `2026-01-27` with different annotation wording | Promoting dev version to prod will break CCOPS `item4` annotation filter | When promoting: update `rules.json` annotation in the same change |
| AFT EFS TLS Lambda — single region | `variables.tf` defaults to `us-east-1` only | EFS file systems in other regions are not covered by the account-level Lambda rule | Update `var.region` per deployment or run AFT customizations per region |
| Two EFS TLS Lambda implementations | `custom-config-rules` (org) and `terraform-aft-account-customizations` (account) both check EFS TLS | Potential duplicate Config findings for the same resource | Decide whether to keep both; `INSERT IGNORE` in the ingest Lambda handles MySQL duplicates, but Config may show two rules per resource |
| EBS CCOPS disabled | `item3` — `enabled: false` | EBS non-compliance never generates ServiceNow incidents | Before enabling: validate annotation substring against real Config findings |
| SQS CCOPS disabled | `item4` — `enabled: false` | SQS non-compliance never generates ServiceNow incidents | Same as EBS; also note annotation change risk with Guard version |
| CCOPS ingest is monthly | Main ECS task runs 1st of each month only | A new violation may wait up to 31 days before generating an incident | Consider more frequent scheduling for high-severity rules, or build an on-demand trigger |

---

## 15. Program Tracking — Jira Allocation

```text
Epic: AWS Cloud Governance Platform [CLOUD-XXXX]
│
├── Story: Org Guard Rules — custom-config-rules [CLOUD-XXXX]
│   ├── Task: Fix EBS Guard snapshot coverage gap [CLOUD-XXXX]
│   ├── Task: Update Guard rule versions as needed [CLOUD-XXXX]
│   └── Task: Review and update excluded accounts list [CLOUD-XXXX]
│
├── Story: Org EFS TLS Lambda — custom-config-rules [CLOUD-XXXX]
│   ├── Task: Maintain lambda_function.py for org-level rule [CLOUD-XXXX]
│   ├── Task: Validate USE2 and USE1 deployments after every code change [CLOUD-XXXX]
│   └── Task: Decide whether to keep both org-level and account-level Lambda rules [CLOUD-XXXX]
│
├── Story: Account-Level AFT Lambda Rules — terraform-aft-account-customizations [CLOUD-XXXX]
│   ├── Task: Update EFS TLS Lambda code as needed [CLOUD-XXXX]
│   └── Task: Evaluate multi-region coverage for AFT EFS TLS Lambda [CLOUD-XXXX]
│
├── Story: OPA Shift-Left — Terrafrom-OPA-Prasanth [CLOUD-XXXX]
│   ├── Task: Resolve Git conflict markers in EBS advisory Rego [CLOUD-XXXX]
│   ├── Task: Decide whether to implement SQS encryption advisory Rego [CLOUD-XXXX]
│   ├── Task: Remove or implement EFS module-usage and SQS module-usage placeholders [CLOUD-XXXX]
│   └── Task: Remove orphaned SQS module-usage registry entry if no Rego is created [CLOUD-XXXX]
│
└── Story: CCOPS Rule Rollout — cloud-ops-governance-platform [CLOUD-XXXX]
    ├── Task: Validate EBS item3 annotation and plan rollout for enablement [CLOUD-XXXX]
    ├── Task: Validate SQS item4 annotation and plan rollout (coordinate with Guard version) [CLOUD-XXXX]
    └── Task: Evaluate ECS ingest frequency (currently monthly — may be too infrequent) [CLOUD-XXXX]
```

### Definition of Done for any story

- [ ] Code change merged to the owning repository
- [ ] Terraform plan reviewed and attached to the Jira ticket
- [ ] Controls deployed and verified in the correct environment and regions
- [ ] OPA changes validated with `opa test` and evaluated against a real or mock plan
- [ ] CCOPS rule changes validated in DynamoDB after apply
- [ ] Required evidence attached to Jira:
  - Git commit or PR link
  - Terraform plan and apply output
  - AWS Config compliance verification (CLI output or screenshot)
  - OPA evaluation output for shift-left changes
  - DynamoDB item verification for CCOPS changes
  - ServiceNow incident or dry-run evidence when CCOPS behaviour changes
- [ ] This runbook updated if any file path, procedure, naming pattern, or behaviour has changed

---

## 16. Contacts and Approvals

| Role | Owner | Contact |
| --- | --- | --- |
| Program Owner | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Cloud Governance Lead | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Security Reviewer | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Platform Operations | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| FinOps Team | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |

---

## 17. Document History

| Version | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-04-08 | Initial single runbook — merged all previous runbooks, added OPA EBS/EFS detail sections and troubleshooting guide |
| 2.0 | 2026-04-08 | Major expansion: added dual-region deployment detail, org-level EFS TLS Lambda, complete CCOPS infrastructure (Aurora MySQL, ECS Fargate schedules, Step Functions, S3, Lambda functions, observability), DynamoDB CCOPS items, ServiceNow actions_policy structure, and Exclusions field |
