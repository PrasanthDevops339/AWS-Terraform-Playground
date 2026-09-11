# AL2023 image factory

Composes the regional ECR module with Image Builder, scan/promotion workers, release records, event routing and monitoring. Pass the primary AWS provider and an `aws.replica` provider for `us-east-1`. The environment roots pin runtime/provider versions and configure separate remote state.

All account, network, upstream-image, certificate, package, trusted-worker and logging inputs are explicit. See `variables.tf` for the typed contract and the repository runbook for deployment prerequisites. This module neither creates a VPC nor selects enterprise-approved artifacts on the caller's behalf.

`manage_registry_configuration=false` deliberately delegates shared registry configuration. If ownership is adopted, preserve all existing rules and import the singleton configurations before applying changes. Missing scan coverage never permits publication.

Package the Lambda source/dependencies with `scripts/package.sh` before planning. The archive provider generates content-addressed build artifacts; Terraform does not build or push containers through a provisioner. The first actual image build is an intentional Image Builder pipeline execution after deployment/preflight.

Factory tests are run from the development test harness, which supplies mocked providers and public test fixtures. Production readiness also requires live acceptance of network, IAM, scanning, replication, notifications and representative workloads.
