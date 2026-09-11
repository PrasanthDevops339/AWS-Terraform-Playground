# Validation record

Validated locally on 2026-09-11. No AWS backend was initialized, no infrastructure was applied, and no real container image was built or published.

| Check | Result |
|---|---|
| Terraform 1.15.8, AWS provider 6.51.0, archive provider 2.7.1 | Exact versions installed; provider dependency locks saved |
| Provider/API schema inspection | Actual pinned Terraform provider schema and installed botocore service models inspected; Terraform MCP was unavailable |
| Formatting | `terraform fmt -check -recursive` passed |
| Development configuration | `terraform -chdir=environments/dev validate -no-tests` passed |
| Production configuration | `terraform -chdir=environments/prod validate` passed |
| Factory Terraform tests | 3 passed using mocked AWS providers |
| ECR module Terraform tests | 2 passed using a separate mocked test root |
| Python unit/API-stub tests | 39 passed |
| Checkov 3.3.17 | 227 passed checks, 0 failed checks, 28 skipped instances across the documented check IDs below; 0 parsing errors |
| Trivy 0.74.0 | 0 critical, 0 high, 0 medium, 1 low remaining source findings, with scoped ECR policy/scanning exceptions |
| Python compilation and shell syntax | Passed for the implementation files |

Development static validation uses `-no-tests` because Terraform's static validator reports a missing aliased provider when inspecting the alternative-module mock harness. Actual `terraform test` execution runs those tests in full and passes. The ECR tests run separately from the two-provider factory harness. This separates configuration validation from executed mock tests; it does not replace tests with a skip.

Tests exercise missing/expired/unsupported scan states, explicit completion, omitted zero counts, paginated findings, suppressed/no-fix Critical findings, duplicate/out-of-order events, account/repository/digest mismatches, deadlines, conditional version allocation, retries, immutable conflicts, final image identity, exact-digest copying, rebuild limits, policy constraints and input validation.

## Scoped scanner exceptions

Exceptions are attached to the relevant resource, not implemented as a global scanner bypass. They require stakeholder review before production:

| Check IDs | Reason and remaining requirement |
|---|---|
| Checkov `CKV_AWS_163`; Trivy `AWS-0030` | Legacy repository basic-scan check. Enhanced scanning is configured at registry level and verified by the release gate/preflight. |
| Trivy `AWS-0032` | Approved pull uses a wildcard principal constrained by `aws:PrincipalOrgID`; other wildcard statements deny access. Native policy tests verify the conditions; effective cross-account access still needs live tests. |
| `CKV_AWS_199` | AMI-encryption check applied to container distribution. ECR uses regional customer-managed KMS keys. |
| `CKV_AWS_109`, `CKV_AWS_111`, `CKV_AWS_356` | Account-root KMS administration and attached-key policy semantics. `Resource: "*"` in a key policy means its attached key; service-use statements have source restrictions. |
| `CKV_AWS_117` | Lambda workers access AWS public service APIs, not private application resources. The build instances use the provided private subnet; no Lambda NAT/VPC dependency is introduced. |
| `CKV_AWS_272` | AWS Signer profile ownership and code-signing enforcement are deferred enterprise integration. Workers use reviewed content-hashed source and restricted deployment/publisher roles; hashes are not claimed to be signatures. |
| `CKV2_AWS_62` | Evidence storage has no downstream S3 event-notification consumer; the workflow writes explicit release evidence. |
| `CKV_AWS_144` | The initial evidence store is regional, encrypted and versioned. Cross-region evidence disaster recovery is a separate enterprise retention decision; container images do replicate. |
| Trivy `DS-0026`, if reported | A CodeBuild CLI worker has no long-running service endpoint for a health check. Its build command exit status is the health signal. |

Trivy scans source configuration with deployment inputs intentionally unspecified. Its findings do not replace a scan of the reviewed, fully resolved plan or live AWS checks. Raw local scanner/test reports are under ignored `reports/`; they contain test/configuration identifiers and are not deployment artifacts.

## Checks still requiring the enterprise environment

- A reviewed plan with real account, backend, network, image, certificate, package, logging and trusted-worker inputs.
- A successful Image Builder build, actual Inspector completion and the controlled vulnerable-image publication-block test.
- Effective IAM denials/organization pulls, cross-region forwarding and exact digest replication.
- Real ECS/EKS application startup, CrowdStrike/Tripwire support decisions and telemetry acceptance.
- Notification subscription delivery and S3 access-log delivery/enterprise audit coverage.
- AWS Signer and evidence-disaster-recovery decisions recorded with the other scoped exceptions.

Use the runbook's saved-plan, policy-check and rollout commands. Apply only the reviewed plan. Roll back consumers/configuration while retaining accepted digests, encryption keys, counters and evidence.
