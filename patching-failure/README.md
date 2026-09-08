# Patch outcome observability

Capture delivered SSM patch-command terminal events from AFT member accounts
into an existing central S3/Splunk pipeline. Distinguish installation success,
scan success, execution failure, non-delivery and unresolved outcomes.

- [Architecture](ARCHITECTURE.md): account identity, regional resources and ownership boundaries.
- [Build and rollout](BUILD-INSTRUCTIONS-infrastructure.md): local tests, source pinning and dormant deployment.
- [Lambda deployment module](modules/patch-outcome-observability/README.md): writer IAM role, policy outputs and one event pipeline per patching region.
- [Payload contract](PAYLOAD-SPEC-patch-outcome-record.md): schema version 2 and interpretation.
- [Central prerequisites](central-prerequisites/README.md): bucket/key policy checks and queue replay.
- [Splunk integration](splunk/README.md): lookup installation and ready-to-use searches.

The deployment module sources `Terrafrom-AWS-Prasanth/terraform-aws-lambda` and
`terraform-aws-sqs` without modifying them. The central archive bucket, key,
policies and existing ingestion remain externally owned.

## Start with the two-region example

`examples/aft-account-customizations/` calls the same module in two regions.
The primary deployment creates the Lambda execution role and common permissions;
the secondary sets `create_writer_role=false` and reuses `module.primary.writer_role_arn`.
Both pipelines and the role belong to one member-account state. Sample tfvars use dummy member accounts
`222233334444` and `333344445555`, and central account `111122223333`.
They are documentation/test values, not deployment targets. The provider's
`allowed_account_ids` guard must match the real member account before deployment.

```bash
terraform -chdir=examples/aft-account-customizations init -backend=false
terraform -chdir=examples/aft-account-customizations validate
terraform -chdir=examples/aft-account-customizations test
python3 -m unittest discover -s tests -v
```

All checked-in Terraform tests mock every AWS provider. Production roots must
use the organization's existing AFT backend and an immutable Git source commit.
The root example defaults to dormant SSM rules; the optional manual canary stays
available. The primary Lambda deployment outputs `central_prerequisites`: merge
these statements into the **existing** central bucket and KMS policies. No central
bucket/key is created, imported or replaced, and no separate IAM module or repository
is required.

The default deployment includes its own role (`create_writer_role=true`) and
requires `organization_id` to render matching central statements. Additional
regions reuse the role. The AFT example includes `moved` blocks for the prior
separate account-module layout in the same state. The code was reported undeployed;
any existing state still needs a reviewed migration plan. See the build guide for
compatibility with earlier names and schema-1 consumers.

A `patched` result means the installation command succeeded, not that the node
is fully compliant. A `scanned` result installs nothing. SSM event delivery is
best effort; this module does not reconcile missing events.
