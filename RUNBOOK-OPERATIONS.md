# Operations Runbook: AWS Encryption Compliance Controls

EBS, SQS, and EFS | Runtime detection, shift-left policy, and CCOPS routing

| Field | Value |
| --- | --- |
| Document Type | Operations Runbook |
| Audience | Cloud Platform Engineers, DevOps, SRE, Security Engineering |
| Last Updated | 2026-04-05 |
| Status | Active |
| Program Runbook | [RUNBOOK-PROGRAM-LEVEL.md](./RUNBOOK-PROGRAM-LEVEL.md) |

## 1. Purpose

This runbook explains how the current EBS, SQS, and EFS encryption controls are wired in code and how to update them safely.

It answers four operational questions:

1. What is being detected.
2. Which repository owns the detection.
3. How the implementation works.
4. How the result is routed into CCOPS and ServiceNow.

## 2. Scope and Operating Model

This document uses the following operating model:

- `custom-config-rules` is the runtime source of truth for Guard-based org Config rules.
- `terraform-aft-account-customizations` is the runtime source of truth for the EFS TLS Lambda rule.
- `Terrafrom-OPA-Prasanth` is the shift-left source of truth.
- `cloud-ops-governance-platform` is the incident-routing source of truth.

Scope note:

- `custom-config-rules` also contains Lambda rule support and an org-level EFS TLS implementation.
- Per the requested runbook scope, Lambda-rule operations are documented here under AFT, not under `custom-config-rules`.

## 3. Repository Map and How Each Repo Works

| Repository | Key Files | How It Works |
| --- | --- | --- |
| `custom-config-rules` | `environments/prd/cpack_encryption.tf`, `modules/conformance_pack/cpack_template.tf`, `modules/conformance_pack/templates/*.yml`, `policies/*/*.guard` | Terraform reads versioned Guard files, renders YAML with `templatefile`, and deploys an organization conformance pack |
| `terraform-aft-account-customizations` | `exceptions/terraform/lambda-rules-enforcement.tf`, `exceptions/terraform/conformance-pack-templates.tf`, `modules/lambda/*`, `modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py` | AFT packages the Lambda, creates the account-level conformance pack, and deploys it into each account |
| `Terrafrom-OPA-Prasanth` | `global-advisory-policies/policies.hcl`, `global-manadatery-policies/policies.hcl`, `*.rego` | CI evaluates Terraform plan JSON against registered advisory and mandatory Rego queries |
| `cloud-ops-governance-platform` | `dynamodb.tf`, `dynamo/rules.json`, `scripts/complianceIngestLambda/*`, `scripts/complianceRulesExecutionLambda/*`, `scripts/serviceNowEventManagerLambda/*` | Terraform loads rule metadata into DynamoDB; CCOPS ingests findings and creates or updates ServiceNow actions |
| `cloud-ops-ecr-image-builder` | `scripts/config_aggregator.py` | Upstream scheduled aggregator reads enabled DynamoDB rules, applies `ingest_policy`, and writes per-rule CSVs that CCOPS ingests |

## 4. Runtime AWS Config Controls

### 4.1 EBS Guard Rule

**Source files**

- `custom-config-rules/environments/prd/cpack_encryption.tf`
- `custom-config-rules/policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard`

**Production version**

- `config_rule_name = "ebs-is-encrypted"`
- `config_rule_version = "2026-01-09"`

**How it works**

1. `environments/prd/cpack_encryption.tf` adds the rule to `policy_rules_list`.
2. `modules/conformance_pack/cpack_template.tf` reads the Guard file from `policies/ebs-is-encrypted/`.
3. `modules/conformance_pack/templates/guard_template.yml` renders the Config rule block.
4. `modules/conformance_pack/cpack_organization.tf` deploys the org conformance pack.

**What it detects**

```guard
rule ebsIsEncrypted when resourceType == "AWS::EC2::Volume" {
    configuration.encrypted == true <<EBS Volumes must be encrypted>>
}
```

**Operational note**

`cpack_encryption.tf` scopes the rule to `AWS::EC2::Volume` and `AWS::EC2::Snapshot`, but the active Guard file only evaluates `AWS::EC2::Volume`. Snapshot coverage is therefore not implemented in the current policy text.

### 4.2 SQS Guard Rule

**Source files**

- `custom-config-rules/environments/prd/cpack_encryption.tf`
- `custom-config-rules/policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard`
- `custom-config-rules/policies/sqs-is-encrypted/sqs-is-encrypted-2026-01-27.guard`

**Production version**

- `config_rule_version = "2025-10-30"`

**Dev / pre-dev version**

- `custom-config-rules/environments/dev/cpack_encryption.tf` uses `config_rule_version = "2026-01-27"`

**What the active production Guard file checks**

```guard
rule sqsIsEncrypted when resourceType == "AWS::SQS::Queue" {
    configuration.SqsManagedSseEnabled == true
        or configuration.KmsMasterKeyId exists
    <<SQS must be encrypted with SSE-SQS or SSE-KMS at the time of creation>>
}
```

**Operational note**

The staging version uses different field casing and a different annotation message. If production is upgraded to `2026-01-27`, CCOPS annotation matching should be reviewed in the same change.

### 4.3 EFS Guard Rule

**Source files**

- `custom-config-rules/environments/prd/cpack_encryption.tf`
- `custom-config-rules/policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard`

**What it checks**

```guard
rule efsIsEncrypted when resourceType == "AWS::EFS::FileSystem" {
    configuration.Encrypted == true <<EFS's must be encrypted>>
}
```

This is the at-rest check only.

### 4.4 EFS TLS Lambda Rule Through AFT

**Source files**

- `terraform-aft-account-customizations/exceptions/terraform/aft-provider.tf`
- `terraform-aft-account-customizations/exceptions/terraform/lambda-rules-enforcement.tf`
- `terraform-aft-account-customizations/exceptions/terraform/conformance-pack-templates.tf`
- `terraform-aft-account-customizations/modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py`
- `terraform-aft-account-customizations/modules/policy-files/efs_tls_compliance.json`

**How it works**

1. `aft-provider.tf` sets the deployment region from `var.region`.
2. `lambda-rules-enforcement.tf` deploys the Lambda module and creates the account-level conformance pack.
3. `conformance-pack-templates.tf` renders the Config rule named `efstlsenforcement_<account_id>`.
4. The Lambda evaluates the EFS resource policy using AWS APIs not available to Guard.

**Default region**

- `exceptions/terraform/variables.tf` defaults `region = "us-east-1"`

**What it detects**

The Lambda:

- calls `DescribeFileSystemPolicy`
- calls `DescribeReplicationConfigurations`
- returns `NON_COMPLIANT` when TLS enforcement is missing
- returns `NOT_APPLICABLE` for deleted resources and replication destinations

**Primary non-compliant annotations**

- `EFS file system has no policy defined`
- `EFS file system has no policy - TLS enforcement not configured`
- `EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)`

## 5. OPA Rules and Placeholders

### 5.1 Implemented Today

| File | Type | What It Covers | Status |
| --- | --- | --- | --- |
| `global-advisory-policies/aws_ebs_001_advise_encryption.rego` | Advisory | EBS volume, EC2 root block device, EC2 attached EBS encryption | Implemented, but file currently contains unresolved merge conflict markers |
| `global-advisory-policies/aws_efs_001_advise_encryption.rego` | Advisory | EFS at-rest encryption and CMK usage | Implemented |
| `global-manadatery-policies/aws_efs_001_mandatory_encryption.rego` | Mandatory | EFS at-rest encryption and CMK usage, including replication destinations | Implemented |

### 5.2 Placeholders and Gaps

| Area | Current State | Operational Meaning |
| --- | --- | --- |
| SQS encryption Rego | No SQS encryption advisory or mandatory Rego file exists | SQS encryption is runtime-only today |
| SQS module-usage registry | `policies.hcl` references `data.terraform.policies.aws_sqs_001_advise_module_usage.warn` | Registry entry exists, but there is no backing `.rego` file in the repo |
| EFS module-usage policy | `aws_efs_001_advise_module_usage.rego` contains only `package advisory` | Placeholder only |
| EBS advisory repo health | `aws_ebs_001_advise_encryption.rego` includes Git conflict markers | Clean this file before relying on CI output as authoritative evidence |

### 5.3 How the OPA Repo Works

1. `policies.hcl` defines the queries and enforcement level.
2. CI generates Terraform plan JSON.
3. `opa eval` or `opa test` executes the registered rules.
4. Advisory rules warn.
5. Mandatory rules return `deny` and block the pipeline.

## 6. CCOPS DynamoDB Rules

### 6.1 How `rules.json` Is Applied

1. `cloud-ops-governance-platform/dynamodb.tf` reads `dynamo/rules.json` with `jsondecode(file(...))`.
2. Terraform writes each item to DynamoDB table `ccops-policy-engine-rules`.
3. Upstream `cloud-ops-ecr-image-builder/scripts/config_aggregator.py` queries enabled rules, reads `ingest_policy`, and writes per-rule CSVs.
4. CCOPS ingests those CSVs, creates `actions` rows, and sends the selected `actions_policy` to ServiceNow processing.

Operationally, this means:

- `Rules` should contain stable substrings of actual Config rule names, not generated full names.
- `Annotations` should contain stable substrings of real Config annotations, not brittle exact copies unless required.

### 6.2 Current Rule Mapping for EBS, SQS, and EFS

| Item | Service | Enabled | Rules Filter | Annotation Filter | Notes |
| --- | --- | --- | --- | --- | --- |
| `item3` / `id=3` | EBS | `false` | `ebs-is-encrypted` | `EBS Volumes must be encrypted` | Defined, not routing incidents |
| `item4` / `id=4` | SQS | `false` | `sqs-is-encrypted` | `SQS must be encrypted` | Defined, not routing incidents |
| `item5` / `id=5` | EFS | `true` | `efs-is-encrypted`, `efstlsenforcement` | `EFS's must be encrypted`, `EFS file system has no policy`, `EFS policy does not enforce TLS` | Active EFS incident rule |

### 6.3 Why Substring Matching Matters

The runtime names generated by the control repos are not stable enough to hard-code end to end:

- Guard rules in conformance packs are emitted as `<account_alias>-<config_rule_name>` and may include pre-dev random suffixes.
- The AFT EFS TLS rule is emitted as `efstlsenforcement_<account_id>`.

For CCOPS, the correct pattern is to store the stable substring in `ingest_policy.Rules`.

## 7. Change Procedures

### 7.1 Update a Guard Rule in `custom-config-rules`

1. Create a new versioned Guard file in `policies/<rule-name>/`.
2. Update `config_rule_version` in `environments/prd/cpack_encryption.tf`.
3. If needed, update `environments/dev/cpack_encryption.tf` as well.
4. Run:

```bash
cd AWS-Terraform-Playground/custom-config-rules/environments/prd
terraform init
terraform plan
terraform apply
```

5. Verify the org conformance pack and the emitted rule names.

### 7.2 Update the EFS TLS Lambda in AFT

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

### 7.3 Update OPA Rules

1. Modify the relevant `.rego` file and `policies.hcl` if needed.
2. Run local evaluation if tooling is available:

```bash
cd AWS-Terraform-Playground/Terrafrom-OPA-Prasanth
opa eval --data global-advisory-policies --input tfplan.json "data.terraform.policies.aws_efs_001_advise_encryption.warn"
opa eval --data global-manadatery-policies --input tfplan.json "data.terraform.policies.aws_efs_001_mandatory_encryption.deny"
```

3. For EBS advisory cleanup, remove merge conflict markers before treating results as valid.

### 7.4 Update CCOPS Rule Routing

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

## 8. Verification Commands

### 8.1 Verify Org Conformance Pack

```bash
aws configservice describe-organization-conformance-packs
aws configservice get-organization-conformance-pack-detailed-status \
  --organization-conformance-pack-name "<account-alias>-encryption-validation"
```

### 8.2 Verify AFT Lambda Rule

```bash
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `efs-tls-enforcement`)].FunctionName'

aws configservice describe-conformance-packs \
  --query 'ConformancePackDetails[?ConformancePackName==`Lambdarulesconformancepack`]'
```

### 8.3 Verify OPA Repository Health

```bash
rg -n '<<<<<<<|=======|>>>>>>>' AWS-Terraform-Playground/Terrafrom-OPA-Prasanth
```

### 8.4 Verify CCOPS Rule State

```bash
aws dynamodb scan \
  --table-name ccops-policy-engine-rules \
  --filter-expression "#en = :val" \
  --expression-attribute-names '{"#en":"enabled"}' \
  --expression-attribute-values '{":val":{"BOOL":true}}'
```

## 9. Known Issues to Review Before Production Changes

| Issue | Why It Matters |
| --- | --- |
| EBS Guard file only checks volumes, not snapshots | Documentation or compliance reporting should not claim snapshot enforcement without a rule change |
| SQS runtime annotation differs between prod and dev Guard versions | CCOPS filters must be reviewed when promoting the new Guard file |
| AFT default region is `us-east-1` | Lambda rule rollout is region-dependent and not automatically dual-region |
| SQS OPA coverage is missing | Shift-left enforcement is incomplete for SQS |
| EFS module-usage policy is a placeholder | Do not represent it as an active advisory |
| EBS advisory Rego has merge conflict markers | CI output may be broken until repaired |

## 10. Document History

| Version | Date | Change |
| --- | --- | --- |
| 2.0 | 2026-04-05 | Rewritten to align with actual repo layout, requested ownership model, AFT Lambda scope, OPA placeholders, and CCOPS rule handling |
