# Build and rollout — patch outcome observability POC

Everything is implemented in `patching-failure/`, a single Terraform root for one
account and one region. The shared module
`../Terrafrom-AWS-Prasanth/terraform-aws-lambda` is a read-only dependency; keep
the two directories side by side so the relative source path resolves.

Patching is performed by the centralized Quick Setup patch policy. This root
does not create or modify patch policies, baselines or associations.

## Requirements

- Terraform >= 1.9, AWS provider >= 6.0 and < 7, archive provider >= 2.4 and < 3.
- An IAM account alias in the POC account; the shared module uses it to prefix names.
- A TFE workspace whose credentials can assume `arn:aws:iam::<account_id>:role/prasa-tfe-assume-role`. That role must be able to create IAM, Lambda, S3, Logs and EventBridge resources and look up the account alias.
- Provider `default_tags` add the `#finops:*` and `admin:environment` tags to every resource. The IAM API documents tag keys as `[\p{L}\p{Z}\p{N}_.:/=+\-@]+`, which does not include `#`. If the first apply rejects the tags on `aws_iam_role.writer`, confirm how your other TFE workspaces tag IAM roles before changing anything.
- The Python 3.13 runtime includes boto3; no layer is added.
- Optional package or log CMKs must be in the same account and region.
- The central archive CMK is used only for archive writes.

## Resources

Default deployment (canary enabled): **23 managed resources**.

| Count | Resource | Purpose |
|---|---|---|
| 1 | IAM role | Lambda execution role with a fixed name and path. |
| 2 | IAM inline policies | `archive`: central S3/KMS writes and SSM/EC2 reads. `runtime`: this function's log group. |
| 4 | Package bucket, public access block, ownership, encryption | Deployment zip, separate from the central archive. |
| 1 | CloudWatch log group | Explicit retention and optional local CMK. |
| 1 | Lambda function (shared module) | Python 3.13, `handler.handler`, 128 MB, 30 s. |
| 1 | S3 package object (shared module) | Zip of `src/`; a hash change redeploys. |
| 4 | Lambda permissions (shared module) | Only the configured rules may invoke. |
| 1 | Lambda async invoke config | 2 retries, 6-hour maximum event age, no destination. |
| 4 | EventBridge rules | Three SSM patterns plus the manual canary. |
| 4 | EventBridge targets | One Lambda target per rule, no DLQ. |

With `enable_canary=false` the count is 20. Restoring the DLQ enhancement adds
3: two SQS queues and one queue policy.

## Local verification

Run from `patching-failure/`:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
python3 -m unittest discover -s tests -v
```

`tests/basic.tftest.hcl` mocks the AWS provider. Its `command = apply` run only
creates mocked resources in temporary test state and inspects the generated
policy JSON. The archive provider runs locally and writes
`patch-outcome-<region>-writer.zip` to the working directory, which is
gitignored. The Python suite fakes the SDK boundary. It covers aggregate status
queries, Scan/Install classification, eventual consistency, deadline
interruption, cache expiry, canaries, replay identity, S3 failures and Splunk
fixture correlation. Local tests cannot run Splunk or prove real SSM event
delivery.

## POC deployment

1. Complete the [central preflight](central-prerequisites/README.md): ownership,
   encryption, explicit Denies and role path/boundary. This writer uses no VPC.
2. On the TFE workspace:
   - Set the **Terraform working directory** to `patching-failure`. The CLI then
     uploads the repository root, so `../Terrafrom-AWS-Prasanth` resolves.
   - Add Terraform variables (not environment variables) with the real
     `account_id`, `organization_id`, `archive_bucket_name` and, when needed,
     `archive_kms_key_arn` and `region` (default `us-east-2`). Keep
     `rules_enabled=false`. See `terraform.tfvars.example`.
3. Queue a plan in TFE, review it, then confirm the apply for that run:

   ```bash
   export TF_CLOUD_ORGANIZATION=<org> TF_WORKSPACE=<workspace>
   terraform init
   terraform plan
   terraform apply
   ```

   Check the plan for 23 creates, no `aws_sqs_*`, no central resources, and the
   finops `default_tags` on each resource. TFE keeps the state; the
   `allowed_account_ids` guard fails the run if the assumed role is in a
   different account.
4. Run `terraform output -json central_prerequisites`. The central owners merge
   these statements into their existing bucket and KMS policies.
5. Run `terraform output -raw canary_command` and execute the command. Confirm
   `FailedEntryCount=0`, then find the EventId in S3 and Splunk.
6. Validate the SSM patterns independently of the canary:

   ```bash
   aws events describe-rule --name patch-outcome-invocation-success --query EventPattern --output text > /tmp/pattern.json
   aws events test-event-pattern --event-pattern file:///tmp/pattern.json --event file://tests/fixtures/ssm-invocation.json
   ```

7. Exercise the failure path. Temporarily remove the central bucket grant, send
   the canary, and confirm the error in the log group and the Lambda `Errors`
   metric (`AsyncEventsDropped` after retries). Restore the grant.
8. Set `rules_enabled=true` and apply through a new reviewed plan. Let the
   Quick Setup patch policy run a scan, or an install on a pilot node, then
   check:
   - a `scanned` or `patched` record appears for the node (not `unknown`); this
     shows association-launched commands resolve through `ssm:ListCommands`;
   - a failure or cancellation case produces the expected `failed`,
     `not-attempted` or `unknown` record;
   - stdout correlation works in Splunk for two instances.

To pause collection, set `rules_enabled=false`. Asynchronous invocations already
accepted may still finish or retry. Package and log storage, requests and KMS
usage can cost money while rules are dormant.

## Enabling the DLQ enhancement later

Uncomment every block marked `ENHANCEMENT (DLQ)`:

- in `main.tf`: the two queue modules, the queue policy, `dead_letter_config`,
  the `depends_on` entries and `destination_config`;
- in `iam.tf`: the SQS statement;
- in `outputs.tf`: the queue URLs.

Then update the assertions in `tests/basic.tftest.hcl` that currently require
no DLQ. This needs the shared `../Terrafrom-AWS-Prasanth/terraform-aws-sqs`
module. Review the plan: it should show 3 additional resources and in-place
updates to the targets, the invoke config and the runtime policy.

## Rollback

Before apply, rollback is reverting the commit. The previous wrapper-module and
AFT layout is recoverable from git history. To remove the POC:

1. Run `terraform plan -destroy -out=destroy.tfplan` and review every resource
   listed.
2. Run `terraform apply destroy.tfplan`.

The package bucket has `force_destroy=true`, and the central archive, key and
policies are never managed here. Remove the merged statements from the central
policies separately if they are no longer needed.

SSM remains best effort with no reconciliation; do not claim complete inventory
coverage or compliance from delivered events alone.
