# Changelog

## 2.0.0

Mandatory WAF protection and AWS provider 6.x `region` support, shipped as one
release.

### Breaking

- `web_acl_arn` is now a **required** variable (no default). Every user pool
  created by this module is associated with a REGIONAL-scope AWS WAFv2 Web ACL
  through a new `aws_wafv2_web_acl_association.main` resource.
- Minimum `hashicorp/aws` provider raised from unpinned to **`>= 6.0.0`**. The
  resource-level `region` argument exists only in AWS provider 6.x.
- `required_version = ">= 1.3"` added to `versions.tf` (previously unset), for
  the `lifecycle { precondition }` blocks and `startswith()`.

### Added

- **WAF association.** `aws_cognito_user_pool` has no native `web_acl_arn`
  argument, so protection is a separate `aws_wafv2_web_acl_association`
  resource linking the pool ARN to a Web ACL ARN in the same Region. No Web ACL
  is created inside this module — source one from a shared `terraform-aws-waf`
  instance and pass its `arn` output in.
- **Optional `region` input** (default `null`). When `null` every resource uses
  the provider-configured Region. Applied to `aws_cognito_user_pool`,
  `aws_cognito_user_pool_domain`, `aws_cognito_identity_provider`,
  `aws_cognito_user_pool_client` and `aws_wafv2_web_acl_association`.

  A `validation` block restricts it to **`null`, `"us-east-1"` or
  `"us-east-2"`** — the Regions this platform deploys into. This is an
  allow-list, not an AWS limitation; widen the `contains([...])` list in
  `variables.tf` when another Region is approved. It constrains the input only,
  not the Region the `aws` provider is configured for.

  Deliberately **not** applied to `data.aws_caller_identity` or
  `data.aws_iam_account_alias` — the AWS provider classifies IAM and STS as
  global services and excludes them from enhanced region support, so adding
  `region` there is a configuration error.
- **Two `precondition` blocks** on `aws_wafv2_web_acl_association.main`, each
  turning an opaque apply-time AWS error into a named plan-time failure:
  - *Region.* The Web ACL's Region must equal the Region this module's
    resources land in. Compared against `local.effective_region`
    (`data.aws_region.current.region`, which resolves `var.region` when set and
    the provider Region when null), not against `var.region` directly.
    `terraform-aws-waf` has its own `region` input, so the Web ACL can be moved
    while `var.region` here stays null — a `var.region`-only check misses that.
  - *Scope.* The Web ACL must be REGIONAL-scope, read from the ARN's
    `regional/` vs `global/` path segment. `terraform-aws-waf` forces
    `scope = "CLOUDFRONT"` ACLs into us-east-1, so a CLOUDFRONT ACL paired with
    `region = "us-east-1"` would satisfy the Region check while still being
    unassociable.
- `data "aws_region" "current"` (taking `region = var.region`), the only new
  data source, supporting the Region precondition.

### Examples

- `examples/complete` — the baseline. Sets no `region`, so everything lands in
  the provider's Region. Gained an `output.tf` asserting
  `user_pool_region == provider_region`.
- `examples/complete-use1` — new. Provider configured for us-east-2, `region`
  set to us-east-1, proving the input end to end. Passes the same region to
  `terraform-aws-waf`, so the whole example runs off one provider
  configuration with no aliases.
- `examples/complete` no longer ships a static `files/metadata.xml` whose SAML
  signing certificate had expired. It generates a throwaway self-signed
  certificate with the `hashicorp/tls` provider, renders the metadata around
  it, and writes it to a gitignored `generated/` directory. The module's public
  interface is unchanged; see `SELF-SIGNED-SAML-CERT.md` for why the path is
  routed through `local_file.saml_metadata.id`.
- The hosted UI domain prefix is suffixed with a random string, since Cognito
  prefix domains are globally unique and repeated applies collided.

### Why this is a major version

Two independent reasons, either sufficient on its own:

- `web_acl_arn` is required with no default, so every existing call site fails
  to plan until it is edited.
- The AWS provider floor moves to 6.x. Released as a minor, a consumer pinned
  `~> 1.0` would pick this up and fail at `init` against an AWS 5.x lock file.

---

## Migration guide (0.1.0 / 1.x → 2.0.0)

Two breaking changes land together: the pool now requires a Web ACL, and the
module now requires AWS provider 6.x. **Do them as two separate commits** —
steps 1-2 are the provider upgrade and should produce no infrastructure change,
steps 3-6 are the WAF work and will create a resource. Splitting them means a
regression can be bisected to one or the other.

Budget for step 4 in particular: it is the one that can silently break
protection that already works.

### Step 1 — Upgrade the AWS provider while still on 1.x

Do this **before** bumping the module version, so provider-only breakage is
isolated from this module's changes. Loosen your own root constraint to allow
6.x, then:

```console
terraform init -upgrade
terraform plan
```

Read the [AWS provider v6 upgrade guide](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-6-upgrade)
for changes unrelated to Cognito. Expect an **empty plan** for the resources
this module manages. Anything else is a provider issue, not a module issue —
resolve it here, before continuing.

Commit `.terraform.lock.hcl` on its own.

### Step 2 — Confirm your Terraform runtime is 1.3+

```console
terraform version
```

`required_version = ">= 1.3"` is new. 1.3 shipped in 2022, so this is usually a
formality, but a pinned CI image may still be older.

### Step 3 — Provision or identify a REGIONAL Web ACL

Two constraints, both enforced by AWS:

- Scope must be **`REGIONAL`**. A CLOUDFRONT-scope Web ACL cannot attach to a
  user pool, and `terraform-aws-waf` places CLOUDFRONT ACLs in us-east-1
  regardless of any `region` you pass it.
- It must be in the **same Region** as the user pool.

Both are checked by preconditions at plan time, so a mistake here fails fast
with a message naming the cause.

```hcl
module "waf" {
  source = "../../../terraform-aws-waf"

  waf_name = "my-app"
  scope    = "REGIONAL"
}

module "cognito" {
  source = "../.."

  # ...existing inputs...
  web_acl_arn = module.waf.arn
}
```

One Web ACL can be shared across many pools — you do not need a `module "waf"`
instance per pool. Prefer a single, centrally managed ACL.

### Step 4 — Check whether the pool is already associated

**Do not skip this even if you believe the pool is unprotected.**
`AssociateWebACL` is 1:1 per resource and **last-writer-wins silently**. If the
pool was already associated out-of-band — the console, an AWS Config
remediation, a security-team stack — the new resource overwrites that
association with no error, then re-asserts it on every subsequent plan.

```console
aws wafv2 get-web-acl-for-resource --resource-arn <user-pool-arn>
```

If that returns a Web ACL you intend to **keep**, import it rather than letting
Terraform create the association. The import ID is `WEB_ACL_ARN,RESOURCE_ARN` —
comma-separated, no spaces:

```hcl
import {
  to = module.cognito.aws_wafv2_web_acl_association.main
  id = "<web_acl_arn>,<user_pool_arn>"
}
```

`import` blocks need Terraform 1.5+. On 1.3 or 1.4:

```console
terraform import 'module.cognito.aws_wafv2_web_acl_association.main' \
  '<web_acl_arn>,<user_pool_arn>'
```

If it returns an ACL you are *replacing*, no import is needed — but confirm
whatever created it will not re-associate later, or the two owners fight on
every apply.

### Step 5 — Check the user pool feature plan

AWS WAF integration requires the **Essentials** or **Plus** feature plan. It is
**not available on Lite**, and associating against a Lite pool fails at apply.
This is the one prerequisite no precondition can catch.

```console
aws cognito-idp describe-user-pool --user-pool-id <user-pool-id> \
  --query 'UserPool.UserPoolTier'
```

This module does not manage `user_pool_tier` — it only sets
`user_pool_add_ons { advanced_security_mode }` — so pools take whatever AWS
defaults to, currently `ESSENTIALS`. Pools explicitly created or imported as
Lite will fail.

Moving a pool from Lite to Essentials **increases its cost**. That is a billing
decision, not a config flag; get it approved before rolling across a fleet.

### Step 6 — Bump the module and apply

Add `web_acl_arn` to every call site. Until you do, `terraform plan` fails with
a missing-required-argument error — and that blocks **all** changes to the
pool, a tag edit or callback URL change included, not just WAF ones. Schedule
the upgrade for a window where that is acceptable.

Expect the plan to show exactly **one resource added**,
`aws_wafv2_web_acl_association.main` (plus the Web ACL itself if you are
creating one). The user pool, its domain, IdP, and clients must show **no
changes** — `region` defaults to `null`, and no resource addresses changed in
this release, so there are no `moved` blocks and no state surgery. Any diff on
the pool itself means something else is going on; stop and investigate.

### Optional — deploy to a non-default Region

Only if you want the pool outside the provider's Region. Pass the same value to
both modules:

```hcl
module "waf" {
  source = "../../../terraform-aws-waf"
  region = "us-east-1"
  scope  = "REGIONAL"
  # ...
}

module "cognito" {
  source      = "../.."
  region      = "us-east-1"
  web_acl_arn = module.waf.arn
  # ...
}
```

Both modules take independent `region` inputs, so moving one without the other
is possible in either direction. The preconditions catch it at plan time. See
`examples/complete-use1`.

This module's `region` accepts only `null`, `"us-east-1"` or `"us-east-2"`;
anything else fails validation at plan time. `terraform-aws-waf` has no such
allow-list, so it will happily build a Web ACL in a Region this module refuses
— the mismatch surfaces as a validation error here rather than a confusing WAF
error.

### Rollback

Pin back to 1.x, remove `web_acl_arn` from the call, and run
`terraform init -upgrade` — note that a lock file already on 6.x still
satisfies an unpinned constraint, so without `-upgrade` you will not actually
return to 5.x.

The association is a standalone resource, so the revert destroys only
`aws_wafv2_web_acl_association.main`. The user pool, its domain, and its
clients are untouched.

Rolling back **disassociates the Web ACL**, returning the pool to the
`Cognito User Pool WAF should be enabled` (Wiz IDP-007) finding state. If you
imported an existing association in step 4, roll back with `terraform state rm`
instead of a destroy, so the pre-existing association survives.

## 0.1.0

- Initial Cognito module.
- Cognito User Pool.
- Optional Cognito domain.
- Multiple User Pool clients.
- Example implementation.
