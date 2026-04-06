# Enterprise Runbook: AWS Encryption Compliance Controls

EBS, SQS, and EFS | Program governance, operations, and implementation guidance

| Field | Value |
| --- | --- |
| Document Type | Enterprise Combined Program, Operations, and Technical Runbook |
| Audience | Program Managers, Cloud Governance Leads, Platform Engineers, Security Engineering, DevOps, SRE |
| Last Updated | 2026-04-05 |
| Status | Active |
| Repository | `AWS-Terraform-Playground` |
| Jira Epic | `<!-- PLACEHOLDER: CLOUD-XXXX -->` |
| Program Owner | `<!-- PLACEHOLDER -->` |
| Technical Owner | `<!-- PLACEHOLDER -->` |
| Security Reviewer | `<!-- PLACEHOLDER -->` |

## 1. Executive Summary

This runbook defines the current enterprise control model for encryption compliance across:

- Amazon EBS
- Amazon SQS
- Amazon EFS

The control stack is implemented in four layers:

1. Org runtime detection with AWS Config Guard rules.
2. Account runtime detection with an AFT-deployed EFS TLS Lambda rule.
3. Shift-left policy enforcement with OPA against Terraform plan JSON.
4. Incident routing and ServiceNow orchestration through CCOPS.

This document is intended to be standalone. It combines:

- program-level ownership and Jira allocation
- operational procedures and validation steps
- implementation details needed to understand how the repositories and rule flows work

## 2. Purpose and Objectives

### 2.1 Purpose

Provide a single runbook that explains:

- what is being detected
- where the controls live
- how the controls are deployed
- how findings are operationalized
- what gaps still exist
- how work should be tracked in Jira

### 2.2 Control Objectives

The current control set is intended to ensure:

- storage and messaging resources are encrypted at rest
- EFS access enforces encryption in transit through TLS
- Terraform changes are reviewed for encryption compliance before apply
- runtime violations can be routed into ServiceNow through CCOPS

### 2.3 Success Criteria

This runbook is considered effective when:

- control ownership is clear
- the implementation path is traceable to the source repositories
- validation steps are repeatable
- Jira evidence can be produced without relying on separate documentation

## 3. Scope

### 3.1 In Scope

| Area | Repository | Purpose |
| --- | --- | --- |
| Org runtime controls | `custom-config-rules` | Guard-based AWS Config rules for EBS, SQS, and EFS at-rest checks |
| Account runtime controls | `terraform-aft-account-customizations` | AFT-driven EFS TLS Lambda rule and account-level conformance pack |
| Shift-left controls | `Terrafrom-OPA-Prasanth` | OPA advisory and mandatory Terraform plan checks |
| Operational incident routing | `cloud-ops-governance-platform` | DynamoDB-backed CCOPS rule definitions and ServiceNow actions |
| Upstream compliance aggregation | `cloud-ops-ecr-image-builder` | Reads enabled rules and generates per-rule CSVs for CCOPS ingestion |

### 3.2 Scope Note

`custom-config-rules` also contains Lambda rule support and an organization-level EFS TLS implementation. For this runbook, the agreed operating model is:

- `custom-config-rules` is the org Guard-rule source of truth
- `terraform-aft-account-customizations` is the AFT Lambda-rule source of truth

That keeps the runtime ownership model consistent for program and operations tracking.

### 3.3 Out of Scope

- non-encryption AWS Config controls outside EBS, SQS, and EFS
- incident procedures outside the CCOPS and ServiceNow integration path
- remediation automation not already present in the referenced repositories

## 4. Dependencies and Assumptions

### 4.1 Dependencies

- AWS Config is enabled in the target accounts and organization
- the organization conformance pack deployment path is operational
- AFT customization pipelines are available for account-level rollout
- Terraform CI can evaluate OPA policies against plan JSON
- CCOPS ingestion and ServiceNow integration are operational

### 4.2 Assumptions

- `custom-config-rules` remains the source of truth for org Guard rules
- `terraform-aft-account-customizations` remains the source of truth for the AFT EFS TLS Lambda rule
- CCOPS continues to match findings by stable rule-name and annotation substrings

## 5. Standards and Control Alignment

The current implementation supports alignment to the following control themes:

| Framework / Standard | Intent | Applies To |
| --- | --- | --- |
| CIS AWS Foundations Benchmark v2.4.1 | Encryption at rest | EBS, EFS, SQS |
| AWS Well-Architected Framework SEC08-BP02 | Protect data at rest and in transit | EBS, EFS, SQS |
| Internal Security and Data Classification Policies | Encryption and handling requirements | `<!-- PLACEHOLDER -->` |
| Audit Evidence Expectations | Traceable policy source, deployment evidence, and incident handling evidence | All in-scope controls |

## 6. Roles and Responsibilities

| Role | Primary Responsibility |
| --- | --- |
| Program Owner | Owns program scope, prioritization, and Jira alignment |
| Cloud Governance Lead | Owns Guard-rule strategy, exclusions, and compliance posture |
| Platform Engineering | Owns Terraform implementation and deployment execution |
| Security Engineering | Reviews control logic, policy intent, and incident severity |
| Operations / SRE | Validates deployments, findings, and ServiceNow flow |

## 7. Control Architecture

| Layer | Trigger | Implementation | Outcome |
| --- | --- | --- | --- |
| Pre-deployment | `terraform plan` in CI | OPA policies in `Terrafrom-OPA-Prasanth` | Warn or block before apply |
| Post-deployment, org-wide | AWS Config resource evaluation | Guard rules in `custom-config-rules` | `COMPLIANT` or `NON_COMPLIANT` findings |
| Post-deployment, per account | AFT customization pipeline | EFS TLS Lambda in `terraform-aft-account-customizations` | `COMPLIANT`, `NON_COMPLIANT`, or `NOT_APPLICABLE` findings |
| Incident generation | Scheduled compliance processing | CCOPS rules in `cloud-ops-governance-platform` | ServiceNow incidents or updates |

### 7.1 End-to-End Flow

```text
Terraform change
    │
    ├─> OPA evaluation in CI
    │      ├─ advisory warn
    │      └─ mandatory deny
    │
Provisioned AWS resource
    │
    ├─> AWS Config Guard rule evaluation
    │
    ├─> AFT EFS TLS Lambda evaluation for EFS in-transit checks
    │
    └─> Config findings consumed by compliance aggregation
             │
             ├─> DynamoDB rule filters in CCOPS
             ├─> MySQL ingest and actions records
             └─> ServiceNow incident create or update
```

## 8. Repository Map and How Each Repo Works

| Repository | Key Files | How It Works |
| --- | --- | --- |
| `custom-config-rules` | `environments/prd/cpack_encryption.tf`, `modules/conformance_pack/*`, `policies/*/*.guard` | Terraform reads versioned Guard files, renders YAML with `templatefile`, and deploys an organization conformance pack |
| `terraform-aft-account-customizations` | `exceptions/terraform/lambda-rules-enforcement.tf`, `exceptions/terraform/conformance-pack-templates.tf`, `modules/lambda/*`, `modules/scripts/efs-tls-enforcement/*` | AFT packages the Lambda, creates the account-level conformance pack, and deploys it into each account |
| `Terrafrom-OPA-Prasanth` | `global-advisory-policies/policies.hcl`, `global-manadatery-policies/policies.hcl`, `*.rego` | CI evaluates Terraform plan JSON against registered advisory and mandatory Rego queries |
| `cloud-ops-governance-platform` | `dynamodb.tf`, `dynamo/rules.json`, `scripts/complianceIngestLambda/*`, `scripts/complianceRulesExecutionLambda/*`, `scripts/serviceNowEventManagerLambda/*` | Terraform loads rule metadata into DynamoDB; CCOPS ingests findings and creates or updates ServiceNow actions |
| `cloud-ops-ecr-image-builder` | `scripts/config_aggregator.py` | Upstream scheduled aggregator reads enabled DynamoDB rules, applies `ingest_policy`, and writes per-rule CSVs that CCOPS ingests |

## 9. Service Control Matrix

### 9.1 EBS

| Control Type | Repository | Implementation | Current Behavior |
| --- | --- | --- | --- |
| AWS Config Guard | `custom-config-rules` | `policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard` | Detects unencrypted EBS volumes |
| OPA advisory | `Terrafrom-OPA-Prasanth` | `global-advisory-policies/aws_ebs_001_advise_encryption.rego` | Intended to warn on unencrypted EBS resources in plan JSON |
| CCOPS rule | `cloud-ops-governance-platform` | `dynamo/rules.json` `item3` | Defined, currently disabled |

### 9.2 SQS

| Control Type | Repository | Implementation | Current Behavior |
| --- | --- | --- | --- |
| AWS Config Guard | `custom-config-rules` | `policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard` | Detects queues without SSE-SQS or SSE-KMS |
| OPA | `Terrafrom-OPA-Prasanth` | Not implemented for SQS encryption | Gap |
| CCOPS rule | `cloud-ops-governance-platform` | `dynamo/rules.json` `item4` | Defined, currently disabled |

### 9.3 EFS

| Control Type | Repository | Implementation | Current Behavior |
| --- | --- | --- | --- |
| AWS Config Guard | `custom-config-rules` | `policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard` | Detects EFS not encrypted at rest |
| AFT Lambda | `terraform-aft-account-customizations` | `modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py` | Detects missing or insufficient TLS enforcement in EFS policies |
| OPA advisory | `Terrafrom-OPA-Prasanth` | `global-advisory-policies/aws_efs_001_advise_encryption.rego` | Warns on missing encryption or CMK usage |
| OPA mandatory | `Terrafrom-OPA-Prasanth` | `global-manadatery-policies/aws_efs_001_mandatory_encryption.rego` | Blocks non-compliant EFS plans |
| CCOPS rule | `cloud-ops-governance-platform` | `dynamo/rules.json` `item5` | Enabled and active |

## 10. Detailed Runtime Implementation

### 10.1 Org Guard Rules in `custom-config-rules`

#### 10.1.1 Production Source of Truth

Primary production file:

- `custom-config-rules/environments/prd/cpack_encryption.tf`

Supporting module:

- `custom-config-rules/modules/conformance_pack/`

#### 10.1.2 Render Flow

1. `cpack_encryption.tf` defines `policy_rules_list` and `lambda_rules_list`.
2. `modules/conformance_pack/cpack_template.tf` reads the Guard file content from `policies/<rule-name>/<rule-name>-<version>.guard`.
3. `modules/conformance_pack/templates/guard_template.yml` renders the Config rule block.
4. `modules/conformance_pack/cpack_organization.tf` applies the final CloudFormation-based conformance pack.

#### 10.1.3 Naming Pattern

Conformance pack name:

```text
<account_alias>-encryption-validation
```

Rendered rule name pattern:

```text
<account_alias>-<config_rule_name><optional-random-id>
```

#### 10.1.4 EBS Guard Rule

Active file:

- `custom-config-rules/policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard`

Current logic:

```guard
rule ebsIsEncrypted when resourceType == "AWS::EC2::Volume" {
    configuration.encrypted == true <<EBS Volumes must be encrypted>>
}
```

Important mismatch:

- `cpack_encryption.tf` scopes EBS to `AWS::EC2::Volume` and `AWS::EC2::Snapshot`
- the active Guard policy only evaluates `AWS::EC2::Volume`

#### 10.1.5 SQS Guard Rule

Production file:

- `custom-config-rules/policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard`

Current production logic:

```guard
rule sqsIsEncrypted when resourceType == "AWS::SQS::Queue" {
    configuration.SqsManagedSseEnabled == true
        or configuration.KmsMasterKeyId exists
    <<SQS must be encrypted with SSE-SQS or SSE-KMS at the time of creation>>
}
```

Staging file:

- `custom-config-rules/policies/sqs-is-encrypted/sqs-is-encrypted-2026-01-27.guard`

Important difference:

- the staging file uses different property casing and a different annotation string

#### 10.1.6 EFS Guard Rule

Active file:

- `custom-config-rules/policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard`

Current logic:

```guard
rule efsIsEncrypted when resourceType == "AWS::EFS::FileSystem" {
    configuration.Encrypted == true <<EFS's must be encrypted>>
}
```

This is the at-rest-only check.

### 10.2 EFS TLS Lambda Through AFT

#### 10.2.1 Control Files

- `terraform-aft-account-customizations/exceptions/terraform/aft-provider.tf`
- `terraform-aft-account-customizations/exceptions/terraform/variables.tf`
- `terraform-aft-account-customizations/exceptions/terraform/lambda-rules-enforcement.tf`
- `terraform-aft-account-customizations/exceptions/terraform/conformance-pack-templates.tf`
- `terraform-aft-account-customizations/modules/lambda/*`
- `terraform-aft-account-customizations/modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py`
- `terraform-aft-account-customizations/modules/policy-files/efs_tls_compliance.json`

#### 10.2.2 Deployment Path

1. `aft-provider.tf` sets the provider region from `var.region`.
2. `variables.tf` defaults that region to `us-east-1`.
3. `lambda-rules-enforcement.tf` instantiates `module "efs_tls_enforcement_compliance"`.
4. The Lambda module packages Python from `modules/scripts/efs-tls-enforcement/`.
5. `conformance-pack-templates.tf` renders and deploys the account-level conformance pack.

#### 10.2.3 Runtime Names

Lambda function naming pattern from `modules/lambda/main.tf`:

```text
<account_alias>-efs-tls-enforcement-function
```

Config rule name from `conformance-pack-templates.tf`:

```text
efstlsenforcement_<account_id>
```

Conformance pack name:

```text
Lambdarulesconformancepack
```

#### 10.2.4 IAM Permissions

The Lambda policy template includes:

- `config:PutEvaluations`
- CloudWatch Logs permissions
- `elasticfilesystem:DescribeFileSystemPolicy`
- `elasticfilesystem:DescribeFileSystems`
- `elasticfilesystem:DescribeReplicationConfigurations`

#### 10.2.5 Compliance Logic

The Lambda returns `NON_COMPLIANT` when:

- the file system has no policy
- the policy does not deny non-TLS access for EFS client actions
- the file system lookup fails
- policy evaluation throws an exception

The Lambda returns `NOT_APPLICABLE` when:

- the resource is deleted
- the file system is an EFS replication destination

Primary non-compliant annotations include:

- `EFS file system has no policy defined`
- `EFS file system has no policy - TLS enforcement not configured`
- `EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)`

## 11. OPA Shift-Left Controls

### 11.1 Registry Files

- `Terrafrom-OPA-Prasanth/global-advisory-policies/policies.hcl`
- `Terrafrom-OPA-Prasanth/global-manadatery-policies/policies.hcl`

These registry files define which queries are active in CI.

### 11.2 Implemented Policies

| File | Query | Function |
| --- | --- | --- |
| `aws_ebs_001_advise_encryption.rego` | `data.terraform.policies.aws_ebs_001_advise_encryption.warn` | Warn on unencrypted EBS resources in Terraform plans |
| `aws_efs_001_advise_encryption.rego` | `data.terraform.policies.aws_efs_001_advise_encryption.warn` | Warn on EFS encryption and CMK gaps |
| `aws_efs_001_mandatory_encryption.rego` | `data.terraform.policies.aws_efs_001_mandatory_encryption.deny` | Block non-compliant EFS plans |

### 11.3 Known Policy Gaps and Placeholders

| Area | Current State | Impact |
| --- | --- | --- |
| SQS encryption Rego | No advisory or mandatory SQS encryption policy exists | SQS encryption is runtime-only today |
| SQS module usage | `policies.hcl` references `aws_sqs_001_advise_module_usage.warn`, but no backing file exists | Registry entry is not backed by an implementation file |
| EFS module usage | `aws_efs_001_advise_module_usage.rego` is a placeholder package only | Advisory exists only on paper |
| EBS advisory repo health | `aws_ebs_001_advise_encryption.rego` contains unresolved merge conflict markers | CI reliability is at risk until corrected |

### 11.4 Local Health Check

```bash
rg -n '<<<<<<<|=======|>>>>>>>' AWS-Terraform-Playground/Terrafrom-OPA-Prasanth
```

## 12. CCOPS Integration

### 12.1 DynamoDB Rule Storage

Source file:

- `cloud-ops-governance-platform/dynamo/rules.json`

Loader:

- `cloud-ops-governance-platform/dynamodb.tf`

Table:

```text
ccops-policy-engine-rules
```

Keys:

- hash key: `source`
- range key: `id`

`actions_policy` and `ingest_policy` are stored as stringified JSON values in DynamoDB.

### 12.2 Upstream Aggregation and Incident Flow

1. `cloud-ops-ecr-image-builder/scripts/config_aggregator.py` queries enabled `aws_config` rules from DynamoDB.
2. It reads:
   - `ResourceTypes`
   - `Rules`
   - `Annotations`
   - `ComplianceType`
3. It writes one CSV per account and per rule.
4. `cloud-ops-governance-platform/scripts/complianceIngestLambda/compliance_ingest.py` loads those rows into MySQL.
5. `cloud-ops-governance-platform/scripts/complianceRulesExecutionLambda/complianceRulesExecution.py` groups by `ruleId`, writes processed CSVs, and inserts `actions`.
6. `cloud-ops-governance-platform/scripts/serviceNowEventManagerLambda/servicenow_eventmanager.py` reads `actions_policy` and creates or updates ServiceNow incidents.

### 12.3 Why Matching Uses Stable Substrings

Config rule names differ by deployment path:

- Guard rules are emitted as `<account_alias>-<config_rule_name>`
- AFT Lambda rules are emitted as `efstlsenforcement_<account_id>`

Because of that, CCOPS `Rules` filters should match stable substrings, not full generated names.

The same principle applies to `Annotations`.

### 12.4 Current EBS, SQS, and EFS Rule Mapping

| Item | Service | Enabled | Rules Filter | Annotation Filter |
| --- | --- | --- | --- | --- |
| `item3` / `id=3` | EBS | `false` | `ebs-is-encrypted` | `EBS Volumes must be encrypted` |
| `item4` / `id=4` | SQS | `false` | `sqs-is-encrypted` | `SQS must be encrypted` |
| `item5` / `id=5` | EFS | `true` | `efs-is-encrypted`, `efstlsenforcement` | `EFS's must be encrypted`, `EFS file system has no policy`, `EFS policy does not enforce TLS` |

### 12.5 Current Operational Meaning

- `item3` exists but is disabled
- `item4` exists but is disabled
- `item5` is enabled and active for EFS incident generation

## 13. Jira Allocation and Delivery Model

Use one epic with four story groups to maintain clear ownership across runtime, shift-left, and incident routing.

```text
Epic: AWS Encryption Compliance Controls [CLOUD-XXXX]
|
+-- Story: Org Guard Rules - EBS, SQS, EFS [CLOUD-XXXX]
|   +-- Task: Review active Guard file versions [CLOUD-XXXX]
|   +-- Task: Update conformance-pack entries in prd/use1/use2 [CLOUD-XXXX]
|   +-- Task: Review excluded accounts and evidence [CLOUD-XXXX]
|
+-- Story: AFT Lambda Rule - EFS TLS [CLOUD-XXXX]
|   +-- Task: Update Lambda code or IAM policy if needed [CLOUD-XXXX]
|   +-- Task: Validate conformance-pack template output [CLOUD-XXXX]
|   +-- Task: Re-run AFT customization for target accounts [CLOUD-XXXX]
|
+-- Story: OPA Controls and Placeholders [CLOUD-XXXX]
|   +-- Task: Correct EBS advisory repo issue [CLOUD-XXXX]
|   +-- Task: Decide whether to implement SQS encryption policy [CLOUD-XXXX]
|   +-- Task: Decide whether to implement EFS and SQS module-usage policies [CLOUD-XXXX]
|
+-- Story: CCOPS Rule Mapping [CLOUD-XXXX]
    +-- Task: Maintain `rules.json` for items 3, 4, and 5 [CLOUD-XXXX]
    +-- Task: Validate DynamoDB item content after apply [CLOUD-XXXX]
    +-- Task: Confirm ServiceNow ticket behavior [CLOUD-XXXX]
```

## 14. Operational Procedures

### 14.1 Update a Guard Rule in `custom-config-rules`

1. Create a new versioned Guard file in `policies/<rule-name>/`.
2. Update `config_rule_version` in `environments/prd/cpack_encryption.tf`.
3. If needed, update `environments/dev/cpack_encryption.tf`.
4. Run:

```bash
cd AWS-Terraform-Playground/custom-config-rules/environments/prd
terraform init
terraform plan
terraform apply
```

5. Verify the org conformance pack and the emitted rule names.

### 14.2 Update the EFS TLS Lambda in AFT

1. Modify the Lambda in `modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py` or IAM policy in `modules/policy-files/efs_tls_compliance.json`.
2. Re-plan the AFT customization:

```bash
cd AWS-Terraform-Playground/terraform-aft-account-customizations/exceptions/terraform
terraform init
terraform plan
```

3. Merge and trigger the AFT customization pipeline for the target account or accounts.
4. Verify:

- Lambda function exists
- Conformance pack `Lambdarulesconformancepack` exists
- Config rule name matches `efstlsenforcement_<account_id>`

### 14.3 Update OPA Rules

1. Modify the relevant `.rego` file and `policies.hcl` if needed.
2. Run local evaluation if tooling is available:

```bash
cd AWS-Terraform-Playground/Terrafrom-OPA-Prasanth
opa eval --data global-advisory-policies --input tfplan.json "data.terraform.policies.aws_efs_001_advise_encryption.warn"
opa eval --data global-manadatery-policies --input tfplan.json "data.terraform.policies.aws_efs_001_mandatory_encryption.deny"
```

3. For EBS advisory cleanup, remove merge conflict markers before treating results as valid.

### 14.4 Update CCOPS Rule Routing

1. Edit `cloud-ops-governance-platform/dynamo/rules.json`.
2. Keep `Rules` and `Annotations` as stable substrings.
3. Apply the change:

```bash
cd AWS-Terraform-Playground/cloud-ops-governance-platform
terraform init
terraform plan
terraform apply
```

4. Validate the item in DynamoDB:

```bash
aws dynamodb get-item \
  --table-name ccops-policy-engine-rules \
  --key '{"source":{"S":"aws_config"},"id":{"N":"5"}}'
```

## 15. Verification and Evidence

### 15.1 Verify Org Conformance Pack

```bash
aws configservice describe-organization-conformance-packs
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name "<account-alias>-encryption-validation"
```

### 15.2 Verify AFT Lambda Rule

```bash
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `efs-tls-enforcement`)].FunctionName'

aws configservice describe-conformance-packs \
  --query 'ConformancePackDetails[?ConformancePackName==`Lambdarulesconformancepack`]'
```

### 15.3 Verify OPA Repository Health

```bash
rg -n '<<<<<<<|=======|>>>>>>>' AWS-Terraform-Playground/Terrafrom-OPA-Prasanth
```

### 15.4 Verify CCOPS Rule State

```bash
aws dynamodb scan \
  --table-name ccops-policy-engine-rules \
  --filter-expression "#en = :val" \
  --expression-attribute-names '{"#en":"enabled"}' \
  --expression-attribute-values '{":val":{"BOOL":true}}'
```

### 15.5 Required Evidence for Jira

- Git commit or PR link
- Terraform plan and apply output or deployment job link
- AWS Config verification screenshot or CLI output
- OPA evaluation output for shift-left changes
- DynamoDB item verification for CCOPS changes
- ServiceNow incident or dry-run evidence when CCOPS behavior changes

## 16. Definition of Done

- Code change is merged to the owning repository.
- Terraform plan has been reviewed and attached to Jira.
- Runtime controls have been deployed in the correct environment.
- OPA changes, if any, have been evaluated or tested.
- CCOPS rule data has been validated in DynamoDB when changed.
- Evidence links are attached to Jira.
- This combined runbook is updated when program or operational behavior changes.

## 17. Known Issues, Risks, and Constraints

| Area | Current State | Risk |
| --- | --- | --- |
| EBS runtime scope | Terraform scope lists volume and snapshot, but active Guard file checks volume only | Snapshot coverage can be overstated if not explicitly called out |
| SQS prod vs dev | Different Guard versions and annotation messages are in use | CCOPS filters can break if production is upgraded without coordinated review |
| AFT region model | AFT customization defaults to `us-east-1` | Lambda-rule rollout is region-dependent and not automatically multi-region |
| SQS OPA coverage | No SQS encryption Rego exists | Shift-left coverage is incomplete |
| EFS module-usage policy | Placeholder only | Advisory coverage is incomplete |
| EBS advisory file | Contains unresolved merge conflict markers | CI behavior may be broken until repaired |
| CCOPS matching | Depends on stable substring matching in `Rules` and `Annotations` | Wording changes can silently break incident routing |

## 18. Contacts and Approvals

| Role | Owner | Contact |
| --- | --- | --- |
| Program Owner | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Cloud Governance Lead | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Security Reviewer | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Platform Operations | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |

## 19. Document History

| Version | Date | Change |
| --- | --- | --- |
| 2.0 | 2026-04-05 | Rewritten as a standalone combined runbook containing the program, operations, and implementation content in a single structured document |
