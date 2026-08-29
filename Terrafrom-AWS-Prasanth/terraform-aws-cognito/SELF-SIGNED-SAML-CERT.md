# Self-Signed SAML Signing Certificate in the Complete Example

How `examples/complete` stopped shipping an expiring certificate — **without
changing the Cognito module at all** — and an honest account of the
alternatives that were considered and rejected.

The implemented solution is Option B in
[section 5](#5-doing-this-without-changing-the-cognito-module): generate the
certificate with the `tls` provider, write the metadata to disk with
`local_file`, and pass the path in a form that defers the module's read to
apply time. The module's `main.tf`, `data.tf`, `variables.tf`, and
`versions.tf` are untouched.

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

## 3. Handing the metadata to the unmodified module

The module reads its metadata from disk, and that behaviour is unchanged:

```hcl
data "local_file" "saml_metadata" {
  filename = var.samlmetadatafile
}
```

So the rendered XML has to become a real file. `saml.tf` writes it:

```hcl
resource "local_file" "saml_metadata" {
  filename = "${path.module}/generated/metadata.xml"
  content  = local.saml_metadata
}
```

`generated/` is gitignored — it is derived state, not source.

### The one subtlety: how the path is passed

This is the part that looks wrong and is not. The example passes:

```hcl
samlmetadatafile = local_file.saml_metadata.id == "" ? "" : local_file.saml_metadata.filename
```

instead of the obvious `local_file.saml_metadata.filename`. The reason is
[section 4b](#4b-across-a-module-boundary-it-fails-at-plan): the plain filename
is a *statically known string*, so it crosses into the module carrying no
dependency, and the module's data source reads it at **plan** time — before the
file exists. On a clean checkout that is a hard failure.

`local_file.saml_metadata.id` is known-after-apply, which makes the whole
conditional unknown at plan, so Terraform defers the module's read to apply.

**Verified against the real module.** With `generated/` absent, planning the
example produces zero local-file errors. Switching that one line to the plain
`.filename` and re-planning produces:

```
Error: Read local file data source error

  with module.cognitotest.data.local_file.saml_metadata,
  on ../../data.tf line 5, in data "local_file" "saml_metadata":
```

Same config, same absent file, one line different. That line is load-bearing,
which is why it carries a comment in `main.tf`.

### Files changed

| File | Change |
|------|--------|
| `examples/complete/saml.tf` | New — `tls` key + certificate, metadata rendering, `local_file` writer |
| `examples/complete/files/metadata.xml.tftpl` | Replaces the deleted static `metadata.xml` |
| `examples/complete/main.tf` | Passes the deferred path; random domain suffix; placeholder URLs |
| `examples/complete/version.tf` | Added `tls`, `random`, `local` providers |
| `examples/complete/.gitignore` | New — ignores `generated/` |

**Module files changed: none.**

## 4. Why the `local` provider needs care across a module boundary

This section explains *why* section 3's odd-looking expression exists. The
obvious way to write it is:

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

and that **fails on a clean checkout**.

**Correction to a common belief: this is not a dead end.** It is frequently
described as an unsolvable chicken-and-egg problem, and that framing is wrong —
the approach works fine once you understand where the dependency is lost. Here
is what actually happens, verified by running each case.

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

### 4d. The costs we accepted

Writing the file to disk is not free, and these apply to the implemented
solution too:

- **It writes a generated artifact into the repo.** Handled with a `.gitignore`
  entry for `generated/`, but it is a file that is pure derived state.
- **It needs a writable working directory.** Terraform Cloud and most CI
  runners give you one, but it is a filesystem dependency the run did not
  previously have.
- **It adds a resource whose only purpose is to launder a value** from memory,
  onto disk, and back into memory in the same run.

These were judged cheaper than changing the module's public interface.

### Verdict on this option

`depends_on` works and needs no module change, but it is the blunt version of
what we actually want. Option B in the next section achieves the same deferral
while affecting only the one data source that needs it, so that is what the
example uses.

---

## 5. Doing this without changing the Cognito module

Everything below leaves the module's `main.tf`, `data.tf`, `variables.tf`, and
`versions.tf` untouched. **Option B is what the example implements.** All of
these were run before being written down; the plan output and errors quoted are
verbatim.

### Option A — `local_file` + `depends_on` on the module call

Covered in 4c. Works, needs no module change, but defers **every** data source
in the module — including `aws_caller_identity` and `aws_iam_account_alias` —
so the user pool name and its tags read `(known after apply)`.

### Option B — `local_file` with a plan-unknown path ✅ CHOSEN

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

This is strictly more surgical than `depends_on`, which is why it is the
implemented solution. The cost is that it is non-obvious: without the comment,
the next reader will "simplify" it back to `local_file.saml_metadata.filename`
and break the clean-checkout plan. That is why `main.tf` carries an eight-line
comment over one line of code.

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
| **B — plan-unknown path ✅** | **No** | **Full except the metadata read** | **Yes** | **Yes** |
| A — `depends_on` | No | Pool name/tags unknown | Yes | Yes |
| C — external script | No | Full | Yes (pre-committed or hooked) | Only with a pre-plan hook |
| D — long-lived committed cert | No | Full | Already in git | Yes |
| E — two-phase `-target` | No | Full | Yes | No |
| `saml_metadata_content` input | **Yes** | Full | No | Yes |

**Option B is the best available without touching the module**: it is the only
one that keeps the rest of the plan intact, works on a clean checkout, needs no
out-of-band step, and runs unmodified on TFE. Its weakness is legibility, which
the comment in `main.tf` addresses.

The last row — adding a `saml_metadata_content` variable to the module — is
marginally cleaner in isolation, since it writes nothing to disk and needs no
trick. It was implemented first and then reverted: it changes the module's
public interface for the benefit of an example, and keeping the module stable
was worth more than avoiding one non-obvious line in example code.

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

The implemented solution was additionally A/B tested against the **real**
module, with `generated/` absent, using dummy AWS credentials (the AWS data
sources fail on credentials, but Terraform still reports every other plan-time
error, so a local-file failure would appear alongside them):

| `samlmetadatafile` set to | `Read local file data source error` count |
|---------------------------|-------------------------------------------|
| `...id == "" ? "" : ...filename` (implemented) | **0** |
| `local_file.saml_metadata.filename` (naive) | **1**, at `../../data.tf line 5` |

Same configuration, same absent file, one line different.

Two corrections worth recording:

- An early version of this document was going to claim the `local` provider
  approach was impossible. Testing showed that is wrong in the single-module
  case and merely inconvenient across a module boundary. The claim was dropped
  rather than published.
- An early verification of Option C reported success against an **empty**
  certificate — the `openssl` call had silently failed and an empty string
  base64-decodes without complaint. The assertions above (length, DER SEQUENCE
  byte, `openssl x509` exit code) were added in response.
