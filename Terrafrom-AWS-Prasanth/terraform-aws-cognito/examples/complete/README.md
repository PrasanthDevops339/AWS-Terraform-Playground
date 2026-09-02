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

## Region

This example sets **no** `region` input on either module, so the user pool, the
Web ACL, and everything else land in the AWS provider's Region (us-east-2).
That is the point of it — it is the baseline that proves the module's `region`
support did not change behaviour for callers who do not use it.

Do not add `region` here. [`../complete-use1`](../complete-use1) is the
cross-Region example; if this one also set `region`, nothing in the repo would
cover the default path.

## Run

```bash
terraform init
terraform plan
terraform apply
```

## Validating the result

```hcl
user_pool_region = "us-east-2"
provider_region  = "us-east-2"
```

The two must be **equal** here. In [`../complete-use1`](../complete-use1) the
same two outputs must **differ** — that pairing is what demonstrates the
`region` input works and is genuinely optional.
