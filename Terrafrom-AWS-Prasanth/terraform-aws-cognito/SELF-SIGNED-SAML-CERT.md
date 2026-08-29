# Self-Signed SAML Signing Certificate in the Complete Example

How `examples/complete` stopped shipping an expiring certificate, what changed
in the module to support it, and an honest account of the alternatives — the
`hashicorp/local` route *is* possible, contrary to how this is usually
described, and [section 5](#5-doing-this-without-changing-the-cognito-module)
documents five ways to solve this **without changing the Cognito module at
all**, if that is a constraint for you.

---

## 1. The problem

`examples/complete` used to ship a static `files/metadata.xml`. Inside it, under
`<X509Certificate>`, sat a hardcoded SAML signing certificate.

Cognito validates that certificate when you create the identity provider. Once
it expired, `terraform apply` on the example failed — the example documented a
module that could no longer be deployed.

Committing a fresh certificate fixes it only until that one expires too. The
expiry date is baked into a file in git, and nothing in CI notices the day it
lapses. The fix has to remove the fixed expiry date, not reset it.

## 2. The approach: generate the certificate during the run

[`examples/complete/saml.tf`](examples/complete/saml.tf) mints a throwaway RSA
key and a self-signed certificate on every run with the
[`hashicorp/tls`](https://registry.terraform.io/providers/hashicorp/tls/latest/docs)
provider, then renders the SAML metadata around it:

```hcl
resource "tls_private_key" "saml_signing" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "saml_signing" {
  private_key_pem = tls_private_key.saml_signing.private_key_pem

  subject {
    common_name  = local.saml_entity_id
    organization = "Terraform AWS Cognito Example"
  }

  validity_period_hours = 87600 # 10 years
  early_renewal_hours   = 720   # regenerate 30 days before expiry

  allowed_uses = ["digital_signature", "cert_signing"]
}
```

`early_renewal_hours` is the part that makes this self-healing: 30 days before
the certificate lapses, Terraform plans a replacement instead of quietly
carrying an about-to-expire certificate.

### Stripping the PEM armor

`tls_self_signed_cert.cert_pem` is PEM — base64 wrapped in
`-----BEGIN CERTIFICATE-----` / `-----END CERTIFICATE-----` with newlines. SAML
metadata wants the bare base64 DER body, so the armor and newlines come off:

```hcl
saml_signing_certificate = replace(
  tls_self_signed_cert.saml_signing.cert_pem,
  "/-----(BEGIN|END) CERTIFICATE-----|\\n/",
  "",
)
```

This is the step that silently breaks if you skip it: Cognito rejects metadata
whose certificate body still contains the PEM headers.

### Rendering the metadata

`files/metadata.xml` was deleted and replaced with
`files/metadata.xml.tftpl`, rendered via `templatefile`:

```hcl
saml_metadata = templatefile("${path.module}/files/metadata.xml.tftpl", {
  entity_id           = local.saml_entity_id
  sso_url             = local.saml_sso_url
  signing_certificate = local.saml_signing_certificate
})
```

## 3. What changed in the module

The module read its metadata from disk and only from disk:

```hcl
data "local_file" "saml_metadata" {
  filename = var.samlmetadatafile
}
```

Generated metadata never touches the disk, so the module needed a second,
optional way in. The change is backward compatible:

| File | Change |
|------|--------|
| `variables.tf` | New optional `saml_metadata_content`. `samlmetadatafile` is now typed `string` with `default = null`, plus a validation that **exactly one** of the two is set. |
| `data.tf` | `data.local_file.saml_metadata` gained `count`, so no file is read when content is passed inline. |
| `main.tf` | New `local.saml_metadata` coalesces the two sources and feeds `provider_details.MetadataFile`. |
| `versions.tf` | Declared the previously implicit `hashicorp/local` provider; added `required_version = ">= 1.3"`. |

```hcl
locals {
  saml_metadata = coalesce(
    var.saml_metadata_content,
    one(data.local_file.saml_metadata[*].content),
  )
}
```

Existing callers passing `samlmetadatafile` are unaffected.

---

## 4. Why not just write the file with the `local` provider?

The obvious alternative is to keep the module untouched, write the rendered
metadata to disk with `local_file`, and pass the path in:

```hcl
resource "local_file" "saml_metadata" {
  filename = "${path.module}/generated/metadata.xml"
  content  = local.saml_metadata
}

module "cognitotest" {
  source           = "../.."
  samlmetadatafile = local_file.saml_metadata.filename
}
```

**Correction to a common belief: this is not impossible.** It is frequently
described as a hard chicken-and-egg problem, and that framing is wrong. But it
fails by default, and the fix has a cost that isn't obvious. Here is what
actually happens, verified by running each case.

### 4a. Within a single module, it works

If the `local_file` resource and the `data.local_file` that reads it live in the
**same** module, Terraform sees the dependency, defers the read, and reports:

```
# data.local_file.read_back will be read during apply
# (depends on a resource or a module with changes pending)
```

`apply` then succeeds. So the naive mental model — "a data source always reads
at plan time, therefore this can never work" — is simply not true.

### 4b. Across a module boundary, it fails at plan

Our case is different: the `data.local_file` lives **inside the child module**,
and the path arrives through an input variable. Running that exact shape:

```
Error: Read local file data source error

  with module.child.data.local_file.saml_metadata,
  on child/main.tf line 3, in data "local_file" "saml_metadata":

The file at given path cannot be read.

+Original Error: open ./generated/metadata.xml: no such file or directory
```

The reason is that `local_file.saml_metadata.filename` is a **statically known
string**. Terraform resolves it to `"./generated/metadata.xml"` immediately, and
that plain string is what crosses into the child module. The dependency edge
does not survive the crossing — the child module sees a literal path with no
indication that a resource is about to create it, so its data source reads
eagerly at plan time, and the file isn't there yet.

This breaks every clean checkout: fresh clones, CI runners, and any `plan` on a
machine where the file was never written.

### 4c. `depends_on` fixes it — and defers every other data source with it

Adding `depends_on` to the module call does make it plan cleanly:

```hcl
module "cognitotest" {
  source           = "../.."
  samlmetadatafile = local_file.saml_metadata.filename

  depends_on = [local_file.saml_metadata]
}
```

But `depends_on` on a module call applies to the **whole module**, not to the
one data source that needs it. In a test where the child module also held a
data source reading a file that already existed and had nothing to do with the
generated one, that unrelated data source was deferred too:

```
# module.child.data.local_file.unrelated will be read during apply
# (depends on a resource or a module with changes pending)
```

In this module that is not hypothetical. `data.tf` also contains:

```hcl
data "aws_caller_identity" "current" {}
data "aws_iam_account_alias" "current" {}
```

Both would become "read during apply." Since `local.account_alias` feeds the
user pool's `name`, the pool name — and everything derived from it, including
tags — goes `(known after apply)`. You trade a readable plan for a workaround,
on a module whose whole job is to be reviewed before apply.

### 4d. The other costs

- **It writes a generated artifact into the repo.** That means a `.gitignore`
  entry, or a dirty working tree in CI, for a file that is pure derived state.
- **It needs a writable working directory.** Terraform Cloud and most CI
  runners give you one, but it's a filesystem dependency the run didn't
  previously have.
- **It adds a resource whose only purpose is to launder a value** from memory,
  onto disk, and back into memory in the same run.

### Verdict on this option

`local_file` + `depends_on` is a legitimate option, and its real advantage is
that it requires **no module change at all**. If you cannot modify the module,
it is one of several workable choices — see section 5.

We chose `saml_metadata_content` because we *could* change the module, and
passing a string to a string input is the direct expression of the intent. It
keeps every other data source readable at plan time, writes nothing to disk, and
adds no resource. The trade is one new variable on the module's public surface.

---

## 5. Doing this without changing the Cognito module

Everything below leaves `main.tf`, `data.tf`, and `variables.tf` in the module
untouched. All of them were run before being written down; the plan output and
errors quoted are verbatim.

### Option A — `local_file` + `depends_on` on the module call

Covered in 4c. Works, needs no module change, but defers **every** data source
in the module — including `aws_caller_identity` and `aws_iam_account_alias` —
so the user pool name and its tags read `(known after apply)`.

### Option B — `local_file` with a plan-unknown path (recommended if you cannot touch the module)

The problem in 4b is that the path is a *statically known* string, so the child
module reads it eagerly. You can make the path unknown at plan time without
`depends_on`, by routing it through an attribute that is known-after-apply:

```hcl
resource "local_file" "saml_metadata" {
  filename = "${path.module}/generated/metadata.xml"
  content  = local.saml_metadata
}

module "cognitotest" {
  source = "../.."

  # local_file.saml_metadata.id is known-after-apply, which makes the whole
  # conditional unknown at plan time. The child module therefore defers its
  # data.local_file read to apply, exactly like depends_on would - but this
  # defers ONLY that one data source.
  samlmetadatafile = local_file.saml_metadata.id == "" ? "" : local_file.saml_metadata.filename
}
```

Verified: the plan shows

```
# module.child.data.local_file.saml_metadata will be read during apply
```

and — unlike Option A — the unrelated data source in the module is **not**
listed as deferred; it still resolves at plan time. `terraform apply` then
completes normally.

This is strictly more surgical than `depends_on`. The cost is that it is
non-obvious: without the comment, the next reader will "simplify" it back to
`local_file.saml_metadata.filename` and break the clean-checkout plan. If you
use it, keep the comment.

### Option C — generate the certificate outside Terraform

Drop the `tls` provider entirely and produce `files/metadata.xml` with a script
that runs before `terraform plan`. The module keeps reading a real file from
disk, exactly as it does today, and the plan stays fully readable.

```bash
#!/usr/bin/env bash
set -euo pipefail

# NOTE: openssl's -subj uses "/" as the RDN separator, so a URL common name
# fails with: Missing '=' after RDN type string. Use a bare hostname.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout saml-signing.key -out saml-signing.crt \
  -days 3650 -subj "/CN=idp.example.com"

CERT=$(openssl x509 -in saml-signing.crt -outform DER | base64 | tr -d '\n')

cat > files/metadata.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="https://idp.example.com/metadata">
  <IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <KeyDescriptor use="signing">
      <KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#">
        <X509Data><X509Certificate>${CERT}</X509Certificate></X509Data>
      </KeyInfo>
    </KeyDescriptor>
    <NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</NameIDFormat>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://idp.example.com/sso"/>
  </IDPSSODescriptor>
</EntityDescriptor>
EOF
```

Verified end to end: the generated XML is well-formed and its
`<X509Certificate>` body decodes to a certificate `openssl` parses.

The `-subj` gotcha is worth noting because the `tls` provider does *not* have
it — `common_name = "https://idp.example.com/metadata"` works fine there, which
is why our `saml.tf` can use the URL directly.

**The catch is Terraform Cloud.** This example uses `cloud {}`, and remote runs
execute `plan` on TFE's workers, which never run your script. You would need to
commit the generated file (defeating the point), move to local execution mode,
or add a pre-plan hook. For a local or CI-driven workflow it is clean; for this
example's TFE backend it is awkward.

### Option D — commit a very long-lived certificate

The lowest-tech answer: generate a certificate once by hand with a 30-50 year
lifetime, commit it, and move on. No providers, no module change, no scripts.

It is not as unreasonable as it sounds for a placeholder example — the failure
mode we hit was a *short*-lived certificate, not a committed one. But it keeps
a fixed expiry date in git that nothing monitors, and it re-creates the exact
class of problem we are fixing, just deferred past anyone's tenure. Avoid dates
beyond 2038 if anything in your toolchain is 32-bit time_t sensitive.

### Option E — two-phase targeted apply (not recommended)

```bash
terraform apply -target=local_file.saml_metadata
terraform apply
```

The first apply writes the file; the second sees it on disk and plans normally.
This works, but `-target` is an escape hatch for recovering from mistakes, not
a workflow. It cannot be expressed as a single reviewed plan artifact, which
makes it unusable in CI or TFE, and it silently trains people to run targeted
applies. Documented here only so you recognise it if you see it.

### Choosing between them

| Option | Module change | Plan readable | Writes to disk | Works on TFE |
|--------|---------------|---------------|----------------|--------------|
| `saml_metadata_content` (chosen) | Yes | Full | No | Yes |
| A — `depends_on` | No | Pool name/tags unknown | Yes | Yes |
| B — plan-unknown path | No | Full except the metadata read | Yes | Yes |
| C — external script | No | Full | Yes (pre-committed or hooked) | Only with a pre-plan hook |
| D — long-lived committed cert | No | Full | Already in git | Yes |
| E — two-phase `-target` | No | Full | Yes | No |

If you cannot change the module, **Option B** is the best of these: it is the
only one that keeps the rest of the plan intact, works on a clean checkout, and
needs no out-of-band step. Its weakness is legibility, which a comment fixes.

---

## 6. Security note

The private key is generated by Terraform and stored **in plaintext in the
example's state**. That is acceptable here only because nothing real depends on
it: the entity ID and SSO URL point at `example.com`, no identity provider is
behind them, and no one authenticates through this pool.

**Do not copy this pattern for a real federation setup.** A real identity
provider issues its own metadata, which it controls and rotates; you pass that
file through `samlmetadatafile`. Terraform should never be the thing minting
your production SAML signing key.

## 7. How this was verified

No AWS resources were created. The example passes `terraform fmt -check
-recursive` and `terraform validate`. The certificate path was applied for real
in a scratch directory, and the rendered output confirmed to be well-formed XML
whose `<X509Certificate>` body base64-decodes into a certificate `openssl`
parses:

```
subject=CN=https://idp.example.com/metadata
notBefore=Aug 29 21:47:49 2026 GMT
notAfter=Aug 26 21:47:49 2036 GMT
```

Every claim in sections 4 and 5 was reproduced as a standalone configuration
before being written down, rather than reasoned about:

- **4a** (same module) — planned and applied successfully.
- **4b** (module boundary, no `depends_on`) — failed at plan; error quoted verbatim.
- **4c** (`depends_on`) — planned successfully, and the unrelated data source
  was confirmed deferred, which is what makes the cost real rather than
  theoretical.
- **Option B** (plan-unknown path) — planned with only the metadata data source
  deferred, unrelated data source still resolved at plan, then applied cleanly.
- **Option C** (openssl) — script run end to end; output asserted to be
  well-formed XML whose certificate body is >500 chars, begins with a DER
  SEQUENCE, and parses under `openssl x509`. The `-subj` RDN-separator failure
  is quoted from the run that hit it.

One correction worth recording: an early version of this document was going to
claim the `local` provider approach was impossible. Testing it showed that is
wrong in the single-module case and merely inconvenient across a module
boundary. The claim was dropped rather than published.
