# Program-Level Runbook: AWS Encryption Compliance Controls

EBS, SQS, and EFS | AWS Config, AFT Lambda, OPA, and CCOPS

| Field | Value |
| --- | --- |
| Document Type | Program-Level Runbook |
| Audience | Program Managers, Cloud Governance Leads, Security and Compliance Leads, Platform Owners |
| Last Updated | 2026-04-05 |
| Status | Active |
| Primary Repository | `AWS-Terraform-Playground` |
| Jira Epic | `<!-- PLACEHOLDER: CLOUD-XXXX -->` |
| Confluence / ADR | `<!-- PLACEHOLDER -->` |
| Slack Channel | `<!-- PLACEHOLDER -->` |
| Program Owner | `<!-- PLACEHOLDER -->` |

## 1. Purpose

This runbook defines the program-level operating model for encryption compliance controls covering:

- Amazon EBS
- Amazon SQS
- Amazon EFS

It standardizes:

- Which repositories own which control layers
- What each control detects
- How work should be split in Jira
- What evidence is required for delivery and audit
- Which implementation gaps are still open

## 2. Scope

### 2.1 In Scope

| Area | Repository | Purpose |
| --- | --- | --- |
| Org runtime controls | `custom-config-rules` | Guard-based AWS Config rules for EBS, SQS, and EFS at-rest checks |
| Account runtime controls | `terraform-aft-account-customizations` | AFT-driven EFS TLS Lambda rule and account-level conformance pack |
| Shift-left controls | `Terrafrom-OPA-Prasanth` | OPA advisory and mandatory Terraform plan checks |
| Operational incident routing | `cloud-ops-governance-platform` | DynamoDB-backed CCOPS rule definitions and ServiceNow actions |

### 2.2 Scope Note

`custom-config-rules` also contains Lambda rule support and an organization-level EFS TLS implementation. Per the requested program model for this runbook, that path is excluded from the primary ownership narrative. This document treats:

- `custom-config-rules` as the org Guard-rule source of truth
- `terraform-aft-account-customizations` as the Lambda-rule source of truth

### 2.3 Services and Control Layers

| Service | Runtime Detection | Shift-Left Detection | Operational Routing |
| --- | --- | --- | --- |
| EBS | AWS Config Guard | OPA advisory | CCOPS `item3` |
| SQS | AWS Config Guard | Not implemented for encryption | CCOPS `item4` |
| EFS | AWS Config Guard and AFT Lambda | OPA advisory and mandatory | CCOPS `item5` |

## 3. Control Architecture

| Layer | Trigger | Implementation | Outcome |
| --- | --- | --- | --- |
| Pre-deployment | `terraform plan` in CI | OPA policies in `Terrafrom-OPA-Prasanth` | Warn or block before apply |
| Post-deployment, org-wide | AWS Config resource evaluation | Guard rules in `custom-config-rules` | `COMPLIANT` or `NON_COMPLIANT` findings |
| Post-deployment, per account | AFT customization pipeline | Lambda rule in `terraform-aft-account-customizations` | `COMPLIANT`, `NON_COMPLIANT`, or `NOT_APPLICABLE` findings |
| Incident generation | Scheduled compliance processing | CCOPS rules in `cloud-ops-governance-platform` | ServiceNow incidents or updates |

## 4. What We Detect and How

### 4.1 EBS

| Control | What Is Detected | How |
| --- | --- | --- |
| AWS Config Guard | Unencrypted EBS volumes | Guard file `custom-config-rules/policies/ebs-is-encrypted/ebs-is-encrypted-2026-01-09.guard` checks `configuration.encrypted == true` |
| OPA advisory | Unencrypted `aws_ebs_volume`, `aws_instance.root_block_device`, and `aws_instance.ebs_block_device` | Rego policy `global-advisory-policies/aws_ebs_001_advise_encryption.rego` |
| CCOPS | Runtime EBS non-compliance for incident generation | `cloud-ops-governance-platform/dynamo/rules.json` `item3` |

### 4.2 SQS

| Control | What Is Detected | How |
| --- | --- | --- |
| AWS Config Guard | Queues without SSE-SQS or SSE-KMS | Guard file `custom-config-rules/policies/sqs-is-encrypted/sqs-is-encrypted-2025-10-30.guard` |
| OPA | No SQS encryption policy implemented today | Gap |
| CCOPS | Runtime SQS non-compliance for incident generation | `cloud-ops-governance-platform/dynamo/rules.json` `item4` |

### 4.3 EFS

| Control | What Is Detected | How |
| --- | --- | --- |
| AWS Config Guard | EFS not encrypted at rest | Guard file `custom-config-rules/policies/efs-is-encrypted/efs-is-encrypted-2025-10-30.guard` |
| AFT Lambda | EFS policy does not enforce TLS for client actions, or no usable policy exists | Lambda `terraform-aft-account-customizations/modules/scripts/efs-tls-enforcement/efs_tls_enforcement.py` calls `DescribeFileSystemPolicy` and `DescribeReplicationConfigurations` |
| OPA advisory | Missing `encrypted`, missing `kms_key_id`, invalid KMS ARN, missing replication destination KMS key | `global-advisory-policies/aws_efs_001_advise_encryption.rego` |
| OPA mandatory | Same EFS encryption and KMS checks, but blocking | `global-manadatery-policies/aws_efs_001_mandatory_encryption.rego` |
| CCOPS | Runtime EFS non-compliance for incident generation | `cloud-ops-governance-platform/dynamo/rules.json` `item5` |

## 5. Repository Ownership Model

| Repository | Program Responsibility | Deployment Model | Program Output |
| --- | --- | --- | --- |
| `custom-config-rules` | Org Guard-rule definitions, versions, exclusions, and conformance-pack rollout | Manual Terraform plan/apply from the management or delegated admin account | AWS Config org conformance pack |
| `terraform-aft-account-customizations` | EFS TLS Lambda packaging, IAM, and account-level conformance pack | AFT account customization pipeline | Per-account Lambda-based Config rule |
| `Terrafrom-OPA-Prasanth` | Rego policies, registry entries, tests, and CI enforcement levels | CI evaluation during Terraform plan | Advisory or blocking policy decisions |
| `cloud-ops-governance-platform` | Rule-to-incident mapping and ServiceNow action configuration | Terraform writes `rules.json` into DynamoDB | Enabled CCOPS rules and incident templates |

## 6. Current Program State and Gaps

| Area | Current State | Program Impact | Jira Placeholder |
| --- | --- | --- | --- |
| EBS runtime scope | `cpack_encryption.tf` scopes EBS to `AWS::EC2::Volume` and `AWS::EC2::Snapshot`, but the active Guard file only evaluates `AWS::EC2::Volume` | Snapshot compliance is not actually implemented in the Guard logic | `<!-- PLACEHOLDER -->` |
| SQS shift-left | No SQS encryption Rego policy exists | SQS is runtime-only for encryption today | `<!-- PLACEHOLDER -->` |
| SQS module usage | `policies.hcl` references `aws_sqs_001_advise_module_usage.warn`, but no corresponding `.rego` file exists | Registry entry is not backed by an implementation file | `<!-- PLACEHOLDER -->` |
| EFS module usage | `aws_efs_001_advise_module_usage.rego` is a placeholder package only | Advisory exists only on paper, not as usable policy logic | `<!-- PLACEHOLDER -->` |
| EBS advisory repo health | `aws_ebs_001_advise_encryption.rego` currently contains unresolved merge conflict markers | CI reliability for EBS advisory must be treated as at risk until corrected | `<!-- PLACEHOLDER -->` |
| CCOPS routing | Rules for EBS, SQS, and EFS exist in `rules.json`; EBS and SQS are disabled, EFS is enabled | Incident routing is partly active and partly staged | `<!-- PLACEHOLDER -->` |

## 7. Jira Allotment Template

Use one epic with four story groups so ownership is clear across runtime, shift-left, and operations.

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

## 8. Definition of Done

### 8.1 Story Exit Criteria

- Code change is merged to the owning repository.
- Terraform plan has been reviewed and attached to the ticket.
- Runtime controls have been deployed in the correct environment.
- OPA changes, if any, have been evaluated or tested.
- CCOPS rule data has been validated in DynamoDB when changed.
- Runbook references stay current.
- Evidence links are attached to Jira.

### 8.2 Required Evidence

- Git commit or PR link
- Terraform plan and apply output or deployment job link
- AWS Config verification screenshot or CLI output
- OPA evaluation output for shift-left changes
- DynamoDB item verification for CCOPS changes
- ServiceNow incident or dry-run evidence when CCOPS behavior changes

## 9. CCOPS Program Mapping

| CCOPS Rule | Service | Status in `rules.json` | Program Meaning |
| --- | --- | --- | --- |
| `item3` / `id=3` | EBS | `enabled: false` | Defined but not actively routing incidents |
| `item4` / `id=4` | SQS | `enabled: false` | Defined but not actively routing incidents |
| `item5` / `id=5` | EFS | `enabled: true` | Active incident rule for EFS encryption findings |

Program teams should treat CCOPS enablement as a separate rollout decision from Guard-rule or Lambda-rule deployment.

## 10. Change Governance Flow

1. Open or link the Jira epic and story.
2. Change the source repository first.
3. Validate deployment and evidence in the owning control plane.
4. Update `rules.json` only when incident routing behavior changes.
5. Attach evidence and approvals.
6. Update this runbook and the operations runbook in the same change window.

## 11. Contacts and Approvals

| Role | Owner | Contact |
| --- | --- | --- |
| Program Owner | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Cloud Governance Lead | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Security Reviewer | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |
| Platform Operations | `<!-- PLACEHOLDER -->` | `<!-- PLACEHOLDER -->` |

## 12. Document History

| Version | Date | Change |
| --- | --- | --- |
| 2.0 | 2026-04-05 | Rewritten to align with the actual repository layout, current rule implementations, Jira allocation needs, CCOPS rule ownership, and known gaps |
