# patch-outcome-observability

Deploy once per member account **and region**. By default this module creates
the Lambda execution role, its archive/enrichment permissions and the regional
event pipeline together. It sources the existing shared Lambda and SQS modules
unchanged; no separate IAM module or repository is needed. The central bucket
and KMS key already exist: this module only renders policy statements for their
owners to merge.

## Inputs

| Input | Default / purpose |
|---|---|
| `create_writer_role` | **true**; create the role with the first Lambda deployment. Set false for additional regions. |
| `writer_role_arn` | null; required when `create_writer_role=false`, using the first deployment's output. Must belong to this member account. |
| `writer_role_name` | `patch-outcome-s3-writer`; same name across member accounts. Used when creating the role. |
| `iam_role_path`, `permissions_boundary_arn` | `/`, null; applied when creating the role. |
| `organization_id` | Required when creating the role and rendering central policies; optional when reusing a role. |
| `archive_bucket_name` | Required existing central bucket; consistent across regions. |
| `archive_s3_prefix` | `patchingsolution-events/outcomes`; consistent across regions. |
| `archive_kms_key_arn` | null for SSE-S3; central CMK for archive writes only. |
| `archive_object_acl` | null or `bucket-owner-full-control`; match the shared archive policy. |
| `name_prefix` | `patch-outcome`; validates final alias/region-derived names. |
| `lambda_package_bucket_name` | null → `<prefix>-pkg-<account>-<region>`; any override must also be unique by region. |
| `lambda_package_kms_key_arn` | null → SSE-S3 package encryption; optional same-account, same-region CMK. |
| `local_kms_key_arn` | null → default log encryption; independent same-account, same-region log CMK. |
| `rules_enabled` | **false**; arm after pilot checks. |
| `enable_canary` | true; creates an enabled rule, manually triggered, without a schedule. |
| `enable_enrichment` | true; bounded SSM queries establish operation and detailed status. |
| `include_instance_tags` | true; tags only for invocation records needing context, not confirmed success/failure. |
| `patch_document_name_prefix` | `AWS-RunPatchBaseline`; also matches Association/WithHooks documents. |
| `invocation_failure_statuses` | Terminal coarse statuses plus supported non-delivery/timeout aliases; includes Terminated. |
| `command_failure_statuses` | Terminal command failure/summary statuses, including RateExceeded. |
| `lambda_log_retention_in_days` | 365 |
| `reserved_concurrency` | null → shared module's `-1` unreserved setting. |
| `log_level`, `tags` | `INFO`, `{}` |

The [AFT example](../../examples/aft-account-customizations/main.tf) calls this
module twice: `primary` creates the role; `secondary` sets `create_writer_role=false`
and `writer_role_arn=module.primary.writer_role_arn`. The same archive and enrichment
inputs go to both regions, so the common IAM policy covers both functions. Role
reuse adds only regional runtime permissions; the owning deployment must grant any
additional archive/enrichment access. Deploy the role owner before separate regional
states, and retain it while any regional function uses the role.

## Shared-source constraints and resource ordering

Sources remain `../../../Terrafrom-AWS-Prasanth/terraform-aws-lambda` and
`../../../Terrafrom-AWS-Prasanth/terraform-aws-sqs`. Pin the enclosing Git package
in production to keep these relative sources reproducible.

The shared modules require an account alias and prepend it to names. Lambda
name is `<alias>-<prefix>-<region>-writer`; queues are
`<alias>-<prefix>-target-dlq` and `<alias>-<prefix>-lambda-dlq` in each region.
The region-specific Lambda input also makes its generated zip filename unique
when two regions share a Terraform root. Name-limit checks fail before creating
the package bucket. The shared module packages only from S3 or an image, so
this wrapper creates a regional package bucket.

Public-access blocks, bucket ownership/encryption, log-group creation and
common and regional IAM permissions precede the shared Lambda module. Event targets wait
for the Lambda permissions, target-queue policy, and asynchronous failure
destination. Deployment principals require account-alias lookup access and the
normal provisioning/package upload permissions; a package CMK also needs the
appropriate deployment-principal KMS access. The runtime writer never reads the
central archive or its deployment package itself.

The package bucket's `force_destroy=true` is for this module-owned deployment
artifact only; the central archive is never managed. Member queues use the
shared module's default SSE-SQS behavior. Their actual encryption and retention
are included in the real-provider pilot checks.

Outputs retain function/rule/log/queue/package destinations and
`writer_lambda_config`, `writer_role_arn` and `writer_role_created`. The ARN output
waits for common IAM permissions before other regional calls consume it.
`canary_command` returns a regional CLI command when enabled. `central_prerequisites`
contains resolved statements for the existing central bucket/key policies when
creating the role, and is null when reusing a role. These are policy statements,
not Terraform resources or replacement policy documents.

See [RESOURCES.md](RESOURCES.md), the root architecture, and the central runbook.
Tests include default dormancy, generated permissions, independent encryption,
name/role validation, create/reuse modes, central statements, toggles and
event-envelope fixtures. The example tests two member accounts in two regions.
