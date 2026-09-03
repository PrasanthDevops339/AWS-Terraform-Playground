# Complete Example

This example demonstrates the `terraform-aws-cognito` module with:

- Cognito User Pool
- SAML identity provider backed by a **generated self-signed** signing certificate
- Hosted UI domain
- Web application client
- Default AWS provider tags

## Everything here is a placeholder

Nothing in this example points at infrastructure anyone owns or uses:

| Value | Placeholder | Note |
| --- | --- | --- |
| SAML entity ID / SSO URL | `https://idp.example.com/...` | Never contacted; no real IdP behind it |
| Callback / logout URLs | `https://app.example.com/...` | Cognito only stores them |
| Hosted UI domain prefix | `testcomplete-<random>` | Prefix domains are globally unique, so the suffix keeps repeated applies from colliding |

## Why the certificate is generated

The example used to ship a static `files/metadata.xml`, and its signing
certificate expired — Cognito rejects SAML metadata with an expired
certificate, so `terraform apply` failed. Committing a replacement just resets
the same clock.

Instead, [`saml.tf`](saml.tf) mints a throwaway RSA key and self-signed
certificate with the [`hashicorp/tls`](https://registry.terraform.io/providers/hashicorp/tls/latest/docs)
provider and renders `files/metadata.xml.tftpl` around it, so the example is
valid on every run. The rendered XML is written to `generated/metadata.xml`
(gitignored) and passed to the module through the existing `samlmetadatafile`
input.

**The module is not modified by any of this.** One subtlety makes that possible:
the path is passed as

```hcl
samlmetadatafile = local_file.saml_metadata.id == "" ? "" : local_file.saml_metadata.filename
```

rather than the obvious `local_file.saml_metadata.filename`, which would fail at
plan time on a clean checkout. Do not simplify it - see
[`SELF-SIGNED-SAML-CERT.md`](../../SELF-SIGNED-SAML-CERT.md) section 5.

**Do not copy this for a real federation setup.** The private key is generated
by Terraform and stored in plaintext in this example's state; a real identity
provider supplies its own metadata, which you commit and point
`samlmetadatafile` at directly.

## Two deployments, two Regions

This directory deploys the module **twice**, from one provider configuration:

| File | `region` input | Lands in |
| --- | --- | --- |
| [`main.tf`](main.tf) | not set | us-east-2 — the provider's Region |
| [`main-use1.tf`](main-use1.tf) | `"us-east-1"` | us-east-1 |

The provider is configured for us-east-2 only ([`version.tf`](version.tf)), and
there are **no aliased providers**. Removing that boilerplate is the point of
AWS provider 6.x enhanced region support.

Both cases are covered in one apply:

- `main.tf` proves the default path still works — a caller who never sets
  `region` is unaffected.
- `main-use1.tf` proves `region` actually moves resources, which is only
  demonstrable because the provider Region differs from it.

Do not set `region` in `main.tf`, and do not change the provider to us-east-1.
Either one collapses the two cases into the same test and silently removes the
coverage.

`main-use1.tf` reuses the SAML certificate and metadata from
[`saml.tf`](saml.tf) rather than generating a second one — one throwaway IdP
identity serves both pools.

## Run

```bash
terraform init
terraform plan
terraform apply
```

## Validating the result

```hcl
user_pool_region      = "us-east-2"   # main.tf         - follows the provider
user_pool_region_use1 = "us-east-1"   # main-use1.tf    - moved by `region`
provider_region       = "us-east-2"
```

`user_pool_region` must **equal** `provider_region`; `user_pool_region_use1`
must **differ** from it. That pairing is the whole assertion.

If `user_pool_region_use1` comes back as us-east-2, `region` did not take
effect — check that the AWS provider actually resolved to 6.x, since the
resource-level `region` argument does not exist in 5.x.

Confirm each pool's WAF association landed:

```bash
aws wafv2 get-web-acl-for-resource --region us-east-2 \
  --resource-arn "$(terraform output -raw user_pool_arn)"

aws wafv2 get-web-acl-for-resource --region us-east-1 \
  --resource-arn "$(terraform output -raw user_pool_arn_use1)"
```

## Cleanup

This directory creates **two** user pools and **two** Web ACLs.

```bash
terraform plan -destroy   # review every resource before destroying
terraform destroy
```
