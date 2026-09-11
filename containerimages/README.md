# containerimages

Native Terraform for an AL2023 x86_64 golden-container factory. AWS EC2 Image Builder builds and tests candidates in `us-east-2`; ECR enhanced scanning / Amazon Inspector supplies vulnerability findings. A separate release workflow blocks Critical findings, publishes immutable versions, and verifies replication to `us-east-1`.

This repository is independent of `Imagebuilder`. No ECR module was found in the supplied Platform modules directory, so ECR uses native Terraform resources under the explicitly authorized fallback.

## Start here

- [Architecture and implementation plan](docs/GOLDEN_CONTAINER_IMAGE_FACTORY_PLAN.md)
- [Deployment, operation and rollback](docs/RUNBOOK.md)
- [Cost controls and estimation inputs](docs/COSTS.md)
- [Validation evidence and remaining cloud acceptance](docs/VALIDATION.md)

Terraform is pinned to **1.15.8**, AWS provider to **6.51.0**, and archive provider to **2.7.1**. Runtime workers use the pinned Python dependencies in `requirements.txt`.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements-dev.txt
bash scripts/package.sh
terraform fmt -check -recursive
terraform -chdir=environments/dev init -backend=false -lockfile=readonly
terraform -chdir=environments/dev validate -no-tests
terraform -chdir=environments/dev test
terraform -chdir=modules/ecr-repository init -backend=false -lockfile=readonly
terraform -chdir=modules/ecr-repository test
python3 -m unittest discover -s tests -v
trivy config .
checkov -d . --framework terraform --skip-path .venv --skip-path .terraform --skip-path .build
```

Terraform tests use mocked AWS providers and no real infrastructure. `tests/fixtures` contains a self-signed test CA and deliberately non-routable package URLs; never deploy these fixtures.

Copy the development `backend.hcl.example` and `terraform.tfvars.example` to their corresponding untracked filenames and supply reviewed enterprise values. The runbook covers the trusted promotion-worker image, registry ownership, notification wiring and required network connectivity. Do not run a production apply from placeholder values.

Infrastructure deployment does not build a container during `terraform apply`. Once development infrastructure and prerequisites have been reviewed, start the Image Builder pipeline and perform the live acceptance checks in the runbook.
