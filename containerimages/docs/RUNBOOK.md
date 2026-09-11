# Deployment and operations

## Prerequisites

Use Python 3.12, Terraform 1.15.8 and the committed provider locks. Supply `access_log_bucket_name` for an existing same-account, primary-Region access-log bucket. Its owner must grant `logging.s3.amazonaws.com` permission to write the factory prefix, constrained to the evidence bucket ARN and account. Confirm delivery and its retention policy.

The S3 backend must already exist with encryption, versioning and native lock-file access. Use an authenticated local deployment role or an established CI identity; never place AWS keys in source, tfvars or build components.

The factory consumes an existing private VPC/subnet. Confirm Docker/SSM support and enterprise host-security coverage for the build AMI, correct root device mapping, working DNS and approved HTTPS access to package sources, public ECR, private ECR, S3, SSM and logging. Security-group CIDRs alone do not provide routing. Use existing enterprise proxies/endpoints as appropriate; do not substitute the default VPC.

Supply a public CA bundle and signed-package repository configuration. Validate them before a plan:

```bash
python3 scripts/validate_enterprise_inputs.py enterprise/ca-bundle.pem enterprise/enterprise.repo
```

Repository configuration must use explicit credential-free HTTPS base URLs, `gpgcheck=1`, `sslverify=1`, and approved GPG keys. The standard AL2023 signing key may already be in the base image; an enterprise mirror that re-signs packages requires its approved key to be provisioned through the platform baseline. Do not point at test fixture URLs.

## Trusted promotion worker

Build the supplied worker Dockerfile through your approved bootstrap image pipeline. It requires a reviewed standard AL2023 parent digest and package snapshot, and installs Skopeo and Python 3.12 with the pinned SDK dependencies. The Docker build context is this repository root:

```bash
docker build --platform linux/amd64 -f worker/Dockerfile \
  --build-arg BASE_IMAGE="$APPROVED_AL2023_DIGEST_URI" \
  --build-arg PACKAGE_RELEASE="$APPROVED_AL2023_RELEASE" \
  -t "$TRUSTED_WORKER_TAG" .
```

Scan and publish that automation image through the established trusted-tool process. Supply its immutable ECR digest in `promotion_worker_image`. It must be in the factory account and `us-east-2`; place it outside the golden/staging image namespaces. No Docker build occurs as a Terraform provisioner. The AWS build/pull permissions for bootstrapping this worker belong to the existing platform pipeline.

CodeBuild runs the publisher as user `factory`. Its runtime receives only the candidate digest as an execution override; it obtains the version and evidence from the ledger. Do not grant application CI identities permission to start/update this project, override its source/buildspec/service role, invoke the evaluator, write the ledger, or assume the publisher role. Administrators and Terraform deployment identities can change the trust boundary and require the existing platform approval controls.

## Shared registry ownership

Before creating a plan, inspect both Regions using read-only APIs:

```bash
aws ecr get-registry-scanning-configuration --region us-east-2
aws ecr get-registry-scanning-configuration --region us-east-1
aws ecr describe-registry --region us-east-2
```

There are two supported ownership modes:

- Default: keep `manage_registry_configuration=false`; the existing registry owner configures enhanced continuous scanning for both factory repositories and replication for `golden/<factory>/`.
- Explicit adoption: preserve existing rules in `additional_scan_rules` and `additional_replication_rules`, import existing singleton configuration into the matching Terraform addresses, and review the complete plan before enabling management. Never let two states manage the same account/Region setting.

The import identifiers for ECR registry scanning and replication are the registry/account ID. Example import addresses for the existing primary settings, after explicit ownership handoff and setting the management input:

```bash
terraform -chdir=environments/dev import -var-file=terraform.tfvars \
  'module.factory.aws_ecr_registry_scanning_configuration.primary[0]' "$ACCOUNT_ID"
terraform -chdir=environments/dev import -var-file=terraform.tfvars \
  'module.factory.aws_ecr_replication_configuration.approved[0]' "$ACCOUNT_ID"
```

Use the corresponding replica scanning address for `us-east-1`. Imports change state; retain the existing state snapshot and ownership record and review the next plan. Do not remove another team's scanning filters or replication destinations. Broad replication rules that include staging must be narrowed before the first build.

## Development rollout

1. Install dependencies, package workers and run local checks from the README.
2. Copy the development example backend/tfvars files and supply enterprise values. Keep them untracked.
3. Connect the factory alert topic to the enterprise notification system during rollout and confirm actual delivery before production. This repository creates the topic but does not invent a notification recipient.
4. Initialize the real development backend and generate a saved plan:

```bash
terraform -chdir=environments/dev init -reconfigure -lockfile=readonly -backend-config=backend.hcl
terraform -chdir=environments/dev plan -var-file=terraform.tfvars -out=factory.tfplan
terraform -chdir=environments/dev show -json factory.tfplan > reports/factory.tfplan.json
python3 scripts/check_plan.py reports/factory.tfplan.json
```

5. Review all resources, account/Region targets, permissions, KMS policies, registry changes, replacements and security-scan exceptions. Apply the reviewed saved plan through the established approval process; do not regenerate a different plan in the apply job.
6. After deployment, run the read-only registry preflight and then start the Image Builder pipeline:

```bash
python3 scripts/preflight.py --account-id "$ACCOUNT_ID" --factory "$FACTORY_NAME"
aws imagebuilder start-image-pipeline-execution \
  --image-pipeline-arn "$PIPELINE_ARN" --region us-east-2
```

7. Verify the live acceptance cases below. Enable weekly scheduling only after this succeeds. Use the production environment root and a separate reviewed plan for production.

No initial `aws_imagebuilder_image` resource is created, so Terraform deployment never silently starts a billable build. `schedule_enabled=false` suppresses the weekly schedule while still allowing intentional manual and bounded remediation builds.

## Release observation

The DynamoDB table uses `RELEASE#<digest>` records for version, status, evidence and eligibility, `SCAN#<region>#<repository>#<digest>` for initial-completion records, and separate control/counter records. A base-image digest has one release record in this AL2023-only factory. Changing the release series affects new digests; it does not re-version existing digests.

Use a consistent DynamoDB read when consuming the catalog. Deploy by digest after checking `status=RELEASED` and `eligible=true`; a semver ECR tag alone does not prove current eligibility. Check the repository URLs from Terraform outputs and verify their returned manifests share the approved digest.

Image Builder logs are under the evidence bucket's `build-logs/` prefix. Workers use `/aws/lambda/<factory>-*`, promotion uses `/aws/codebuild/<factory>-promote`, and Step Functions uses `/aws/vendedlogs/states/<factory>-release`. State-machine logs include workflow execution data: digests, timestamps, build metadata and failure details. Secret values are never passed into the workflow; release evidence contains identifiers and findings summaries. The embedded SPDX SBOM and package TSV can be inspected from the accepted image without running its entrypoint.

## Failure and retry

| Failure | Expected behavior and recovery |
|---|---|
| Critical finding, including no fix or suppressed | No official publication. Update the reviewed parent/package snapshot and rebuild. |
| Scan pending or completion event absent | Wait for explicit event/API completion evidence. Fail at the deadline; inspect EventBridge/Inspector coverage. |
| Unsupported/expired/failed scanning | Block. Correct coverage/source support and build a new candidate; do not force a pass. |
| Publisher or authentication failure | No success signal; workflow records failure. Inspect project logs and permissions before a controlled retry. |
| Immutable tag conflict | Fail. Investigate ledger/tag ownership; never overwrite or reuse the tag. |
| Replication delayed | Source image may exist, but catalog stays ineligible. Verify replication settings, target repository and digest. |
| New Critical finding after release | Withdraw catalog eligibility, alert owners and request bounded remediation builds. Existing pulls/workloads continue until platform/application action. |

Duplicate event delivery does not allocate another version. Replays of the same Image Builder execution do not start another Step Functions execution. For a failed workflow whose underlying problem has been corrected, a designated operator may run `python3 scripts/retry_release.py --state-machine-arn "$STATE_MACHINE_ARN" --digest "$DIGEST"`. This requires `states:StartExecution` on this state machine and rechecks the original build and current scan before any copy; it never edits the ledger or overrides a verdict. Wait for the prior execution to terminate before retrying. Withdrawn releases require a new candidate. Preserve the assigned version and evidence if diagnosing an interrupted publisher. Do not edit DynamoDB records to simulate a passed scan.

Remediation builds are limited to one per day and three per source revision. They do not select a new upstream digest or package snapshot automatically. Repeated no-fix findings require source changes and stakeholder review instead of an unbounded rebuild loop.

## Live acceptance

- Prove a clean AL2023 candidate passes Image Builder tests and Inspector, publishes a version, and has identical source/destination digests.
- Use an isolated controlled vulnerable fixture to prove a Critical finding blocks publication, including the no-fix policy. Verify timeout, missing evidence and wrong-digest cases.
- Prove application roles cannot pull staging or publish approved images; test an approved consumer from another organization account and a denied external principal.
- Verify duplicate events, parallel candidates and publisher retry behavior against the live ledger.
- Run representative ECS/EKS application smoke tests with non-root identity, trust, runtime dependencies, writable mounts and selected runtime security integration.
- Prove alert subscription delivery, dead-letter handling, registry forwarding, scheduled-build freshness and release withdrawal behavior.
- Confirm enterprise CloudTrail/S3 data-access audit coverage, vendor acceptance and any documented scanner exceptions before production.

Local mocks do not establish any of these live outcomes.

## Rollback

Restore consumers to a previously accepted digest and the prior approved automation/configuration version. Keep releases, keys, counters and evidence. Revert shared registry configuration only through its owner with a reviewed plan. Do not destroy infrastructure, restore state in isolation, change immutable tags or reuse patch numbers. Inspect downstream digest usage before retiring an old version.
