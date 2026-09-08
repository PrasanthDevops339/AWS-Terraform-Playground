# Build and rollout — patch outcome observability

Implementations live entirely in `patching-failure`. Shared modules under
`Terrafrom-AWS-Prasanth` are read-only dependencies. Keep their relative source
paths intact inside the Git package; all integration adaptations belong here.

## Deployment shape and contracts

Call `modules/patch-outcome-observability` once per region. The primary call
uses the default `create_writer_role=true`: supply the actual organization ID,
existing central bucket/prefix/key, optional ACL, role path/boundary and enrichment
flags. The module creates the Lambda execution role and common inline policy
alongside the regional resources. It exports `writer_role_arn` and resolved
`central_prerequisites` for the **existing** central bucket and KMS policies.

Additional regions set `create_writer_role=false` and pass
`writer_role_arn=module.primary.writer_role_arn`, with the same archive/enrichment
settings. No separate account module or IAM repository is required.
The primary deployment creates 26 resources and each additional region creates
24 with the default canary: regional package bucket/object, runtime policy,
Lambda/log group, three SSM rules plus canary, targets/permissions and two queues.
Two regions create 50 managed resources. Central infrastructure is referenced;
only its owners merge the generated policy statements into their existing policies.

The example root owns both regions and the role in one member-account state.
AFT repeats that root in separate member states. IAM is account-wide: enable
role creation in exactly one call per account. If splitting states later, deploy
the owning region first and pass its role ARN to the other regional states. Keep
the owning deployment while any regional Lambda still uses the shared role.

Requirements: Terraform >=1.9, AWS provider >=6.0,<7, archive provider >=2.4,<3,
a usable IAM account alias, and AFT deployment credentials with provisioning,
account-alias lookup and package access. Python 3.13 runtime includes boto3;
no runtime layer or dependency installation is added. Optional package/log CMKs
must be local to their region/account and authorize their respective consumers.
The central archive CMK is used only for archive writes.

## Reproducible AFT sourcing

For local development, run the supplied example in the full checkout. For a
existing AFT customization repository, use the same literal Git source in each
regional module call, pinned to the **full reviewed commit** of this enclosing repository:

```hcl
# Replace REVIEWED_COMMIT with the full commit containing these changes before init.
source = "git::ssh://git@github.com/PrasanthDevops339/AWS-Terraform-Playground.git//patching-failure/modules/patch-outcome-observability?ref=REVIEWED_COMMIT"
```

This is a module-block source line, not a complete Terraform configuration. Terraform downloads the enclosing package so sibling shared
module paths resolve. Do not copy only the regional module directory or use a
floating branch for fleet rollout. Use AFT's existing backend/providers and
commit the deployment root's provider lock file. The supplied root lock includes
registry checksums; refresh Linux platform checksums in the release environment
if the AFT runner requires them.

## Local verification

Run from `patching-failure/`:

```bash
terraform fmt -check -recursive
terraform -chdir=modules/patch-outcome-observability init -backend=false
terraform -chdir=modules/patch-outcome-observability validate
terraform -chdir=modules/patch-outcome-observability test
terraform -chdir=examples/aft-account-customizations init -backend=false
terraform -chdir=examples/aft-account-customizations validate
terraform -chdir=examples/aft-account-customizations test
python3 -m unittest discover -s tests -v
```

Terraform suites mock **all** AWS providers; their `command=apply` cases apply
only mocked resources to temporary test state. They inspect actual generated
policy JSON and the shared modules' resolved outputs. No AWS credentials or
cloud resources are used. Run `tflint` where installed with the supplied config;
report its absence rather than claiming it ran. Do not format or edit child
source modules to resolve unrelated upstream lint findings.

The Python suite fakes the SDK boundary and validates aggregate status queries,
Scan/Install classification, eventual consistency, deadline interruption, cache
expiry, canaries, replay identity, S3 failures, lookup configuration and fixture
correlation. Local tests cannot execute the Splunk search engine or prove real
SSM event delivery. Test event envelopes live under `tests/fixtures/`; the native
Terraform suite compares them with generated JSON patterns.

Verification on 2026-09-08 used local Terraform **1.15.8**, AWS provider **6.62.0**
and archive provider **2.8.0**, with backend initialization disabled and all AWS
providers mocked. Formatting, module/example validation, **41 Terraform tests**
and **27 Python/Splunk contract tests** passed. `tflint` is unavailable locally.
An isolated migration fixture also used [shared test state](https://developer.hashicorp.com/terraform/language/tests#modules-state)
to plan the previous account-module addresses into the included-role layout:
both IAM moves were recognized and all 50 managed resources were unchanged.
That extra fixture ran under Terraform 1.15.8 outside the checked-in suite; it
does not raise the module's 1.9 floor or verify an actual deployed state. Live AFT
execution assumes the existing remote backend and still requires the pilot below.

## Dormant pilot using real values

The provided member tfvars examples contain **dummy** accounts `222233334444`
and `333344445555`; central `111122223333` is also dummy. They are not deployable
credentials or verified resources. Replace sample values with real member/central
identifiers before a live pilot. Existing ingestion is assumed available; verify
that it includes the outcomes prefix and intended sourcetype.

1. Complete the [central preflight](central-prerequisites/README.md), including
   ownership, central encryption, explicit Denies, role path/boundary and any
   organizational VPC requirements. This implementation uses no VPC attachment.
2. Run one AFT member customization in two regions with `rules_enabled=false`.
   Review the real-provider plan: one identity, regional package buckets, no
   central resource ownership and the expected allowed account ID. Use the
   existing AFT remote backend. In the configured deployment root, save a plan:

   ```bash
   terraform plan -var-file=member-real.tfvars -out=patch-outcome.tfplan
   terraform show -no-color patch-outcome.tfplan
   ```

   Review the saved plan and obtain the normal deployment approval before applying
   that artifact through AFT. `member-real.tfvars` must contain the actual values;
   the dummy example files are for documentation and mocked tests only.
3. Export `terraform output -json central_prerequisites`; central owners merge
   the statements and retain their current policies, encryption and ingestion.
4. Verify actual queue retention (1209600), SSE-SQS, function/log names, local
   encryption and the async destination. Send the two `canary_commands`; check
   PutEvents `FailedEntryCount=0` and find each EventId in S3 and Splunk.
5. Validate the SSM patterns independently of the canary. For example, from a
   real initialized example root (substitute profile/region as appropriate):

   ```bash
   aws events describe-rule --name patch-outcome-invocation-success --region us-east-1 --query EventPattern --output text > /tmp/patch-outcome-pattern.json
   aws events test-event-pattern --event-pattern file:///tmp/patch-outcome-pattern.json --event file://../../tests/fixtures/ssm-invocation.json --region us-east-1
   ```

   Repeat failure/command fixtures and confirm unrelated documents/nonterminal
   events do not match. AWS TestEventPattern checks matching, not SSM delivery.
6. Exercise target delivery failure and Lambda write failure in an isolated
   pilot test window. Restore permissions, inspect each queue envelope, and
   replay using the central runbook. Account for configured delivery retry/event
   age rather than assuming messages arrive in the queue immediately.
7. Arm only the pilot member. Check actual Scan/Install outcomes, a multi-step
   document, cancellation/non-delivery, and a two-instance stdout correlation.
   Verify duplicate replay leaves Splunk counts unchanged. Then enable the
   remaining accounts through reviewed AFT batches.

To pause new SSM collection, set `rules_enabled=false`; accepted asynchronous
invocations may still finish/retry. Keep canary/queues available. Package and log
storage, requests and KMS can cost money while rules are dormant. Monitoring and
notifications stay in the existing Splunk/operator workflow; queue contents need
attention before their fourteen-day retention expires.

## Compatibility and IAM ownership migration

The code was reported undeployed. The example includes two `moved` blocks in
`moved.tf` for a prior same-state layout using `module.patch_outcome_account`:

| Previous resource address | New address |
|---|---|
| `module.patch_outcome_account.aws_iam_role.writer` | `module.primary.aws_iam_role.writer[0]` |
| `module.patch_outcome_account.aws_iam_role_policy.writer` | `module.primary.aws_iam_role_policy.archive[0]` |

Names, role path, trust and common permissions are preserved by this refactor;
regional runtime-policy addresses are unchanged. These blocks do nothing for a
new deployment. For an existing deployment, retain a protected state backup and
review a saved real-provider plan showing IAM moves with no role replacement or
permission loss before applying. Adjust addresses for a differently named caller;
these moves cannot migrate resources between different state files. Keep the
primary provider mapped to the same member account. Mock tests do not validate
migration against an actual deployed state.

Before any apply, rollback is reverting this refactor. After a same-state move
has been applied, restore the prior code with reverse `moved` blocks in the root,
then review a saved plan before applying; reverting files alone can propose a
role replacement. Preserve the original state backup and reviewed plans for recovery.

Earlier single-region versions also differ in regional Lambda/package names and
emit schema 1. Their state and downstream consumers require a separate migration
review. SSM remains best effort with no reconciliation; do not claim complete
inventory coverage or compliance from delivered events alone.
