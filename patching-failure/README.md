# Patch outcome observability (single-account POC)

Patching runs from the organization's **centralized AWS Quick Setup patch
policy**. This solution only observes it: patch policies run `AWS-RunPatchBaseline`
through State Manager associations, SSM publishes command and invocation status
events to EventBridge, and a writer Lambda records each terminal outcome in an
existing central S3/Splunk pipeline. It tells apart installation success, scan
success, execution failure, non-delivery and unresolved outcomes.

This directory is a **single-account, single-region Terraform root**. It calls
the shared `../Terrafrom-AWS-Prasanth/terraform-aws-lambda` module directly;
there is no wrapper module and no AFT example.

- [Architecture](ARCHITECTURE.md): resources and ownership boundaries.
- [How it works](HOW-IT-WORKS.md): event flow, classification and failure visibility.
- [Build and rollout](BUILD-INSTRUCTIONS-infrastructure.md): local tests, resource list and POC deployment.
- [Payload contract](PAYLOAD-SPEC-patch-outcome-record.md): schema version 2 and interpretation.
- [Central prerequisites](central-prerequisites/README.md): bucket/key policy checks and replay.
- [Splunk integration](splunk/README.md): lookup installation and ready-to-use searches.

## Layout

| File | Contents |
|---|---|
| `versions.tf` | Terraform/provider constraints, `cloud {}` for TFE, one `aws` provider assuming `prasa-tfe-assume-role` in `var.account_id` with the finops `default_tags`. |
| `variables.tf` | `account_id`, `region`, `organization_id`, `archive_bucket_name` plus optional tuning. |
| `data.tf` | Caller identity, account alias, partition, region. |
| `main.tf` | Package bucket, log group, `module "writer_lambda"`, async retries, EventBridge rules/targets, and the **commented-out DLQ enhancement**. |
| `iam.tf` | Writer role, central archive/enrichment policy, logs runtime policy. |
| `outputs.tf` | Function, rules, role, `canary_command`, `central_prerequisites`. |
| `src/handler.py` | Lambda code (Python 3.13, boto3 from the runtime). |
| `tests/` | `basic.tftest.hcl` (mocked AWS) and the Python handler/Splunk contract tests. |

## Quick start

```bash
cd patching-failure
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
python3 -m unittest discover -s tests -v
```

All Terraform tests mock AWS, so no credentials or TFE login are needed
(`-backend=false` skips the `cloud {}` block). To deploy the POC through TFE:

1. On the TFE workspace, set **Terraform working directory** to `patching-failure`,
   so the sibling `Terrafrom-AWS-Prasanth` modules are uploaded, and add the
   Terraform variables from [terraform.tfvars.example](terraform.tfvars.example):
   `account_id`, `organization_id`, `archive_bucket_name`, and optionally `region`
   (default `us-east-2`).
2. Queue the run:

   ```bash
   export TF_CLOUD_ORGANIZATION=<org> TF_WORKSPACE=<workspace>
   terraform init
   terraform plan    # runs in TFE; review: 23 creates, no aws_sqs_*
   terraform apply   # or confirm the reviewed run in the TFE UI
   ```

SSM rules are dormant (`rules_enabled=false`) until the canary record is found
in S3 and Splunk. Give the `central_prerequisites` output to the central bucket and
KMS owners to merge; no central resource is created, imported or replaced.

## Basic path vs. enhancement

The POC deploys only the basic path. The SQS dead-letter queues (EventBridge
target DLQ and Lambda on-failure destination) are **commented out** in
`main.tf`, `iam.tf` and `outputs.tf`, each marked `ENHANCEMENT (DLQ)`. Until
they are restored, failed deliveries are visible only in the Lambda logs and
CloudWatch metrics; see [HOW-IT-WORKS.md](HOW-IT-WORKS.md).

A `patched` result means the installation command succeeded, not that the node
is fully compliant. A `scanned` result installs nothing. SSM event delivery is
best effort; nothing here reconciles missing events.
