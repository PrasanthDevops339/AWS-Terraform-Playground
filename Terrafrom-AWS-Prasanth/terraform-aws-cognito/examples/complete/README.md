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
|-------|-------------|------|
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
valid on every run. The rendered XML is passed to the module through the
`saml_metadata_content` input rather than a file on disk.

**Do not copy this for a real federation setup.** The private key is generated
by Terraform and stored in plaintext in this example's state; a real identity
provider supplies its own metadata, which you pass via `samlmetadatafile`.

## Run

```bash
terraform init
terraform plan
terraform apply
```
