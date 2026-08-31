# Changelog

## Unreleased

No module changes. Example-only fix:

- `examples/complete` no longer ships a static `files/metadata.xml` whose SAML
  signing certificate had expired. It now generates a throwaway self-signed
  certificate with the `hashicorp/tls` provider, renders the metadata around it,
  and writes it to a gitignored `generated/` directory for the module to read.
- The hosted UI domain prefix is suffixed with a random string, since Cognito
  prefix domains are globally unique and repeated applies collided.
- The module's public interface is unchanged; the example still passes
  `samlmetadatafile`. See `SELF-SIGNED-SAML-CERT.md` for why the path is routed
  through `local_file.saml_metadata.id`.

Documentation:

- Added a **Migration guide (0.1.0 / 1.x → 2.0.0)** to the `2.0.0` entry below,
  covering the Web ACL scope/region and user pool feature plan prerequisites,
  the import path for pools that already have a Web ACL attached, and rollback.

## 2.0.0

- **Breaking:** `web_acl_arn` is now a required variable (no default). Every
  Cognito User Pool created by this module must be associated with a
  REGIONAL-scope AWS WAFv2 Web ACL, via a new `aws_wafv2_web_acl_association.main`
  resource.
- **Breaking:** minimum `hashicorp/aws` provider version raised to `>= 5.26.0`.
- Consumers should source the Web ACL from a shared `terraform-aws-waf`
  module instance and pass its `arn` output in as `web_acl_arn`.

### Migration guide (0.1.0 / 1.x → 2.0.0)

Work through these in order. Steps 1 and 2 are prerequisites that fail only at
**apply** time if skipped — neither is validated by this module. Step 4 is the
one that can silently break something that already works, so do not skip it
even if you believe the pool is unprotected.

#### 1. Provision or identify a REGIONAL Web ACL

Two constraints, both enforced by AWS rather than by this module:

- The Web ACL must be **`scope = "REGIONAL"`**. A CLOUDFRONT-scope ACL cannot
  attach to a user pool.
- The Web ACL must be in the **same region** as the user pool.

`examples/complete/main.tf` shows the intended wiring:

```hcl
module "waf" {
  source = "../../../terraform-aws-waf"

  waf_name = "testcomplete"
  scope    = "REGIONAL"
}

module "cognitotest" {
  source = "../.."

  # ...existing inputs...
  web_acl_arn = module.waf.arn
}
```

One Web ACL can be shared across many pools — you do not need a `module "waf"`
instance per pool. Prefer a single, centrally managed ACL and pass its ARN in.

#### 2. Check the user pool feature plan

AWS WAF integration requires the **Essentials** or **Plus** feature plan. It is
**not available on Lite**, and associating against a Lite pool fails at apply.

This module does not manage `user_pool_tier` — it only sets
`user_pool_add_ons { advanced_security_mode }` (`main.tf`) — so pools take
whatever AWS defaults to, currently `ESSENTIALS`. Pools explicitly created or
imported as Lite will fail. Check before upgrading:

```console
aws cognito-idp describe-user-pool --user-pool-id <user-pool-id> \
  --query 'UserPool.UserPoolTier'
```

Moving a pool from Lite to Essentials increases its cost. This is a billing
decision, not just a config flag — get it approved before rolling the upgrade
across a fleet.

#### 3. Add `web_acl_arn` to every module call

`web_acl_arn` has no default, so until it is supplied `terraform plan` fails
with a missing-required-argument error. Note that this blocks **all** changes
to the pool — a tag edit, a callback URL change, anything — not only
WAF-related ones. Plan the upgrade for a window where that is acceptable.

#### 4. Check whether the pool is already associated

`AssociateWebACL` is 1:1 per resource and **last-writer-wins silently**. If the
pool was already associated out-of-band — the console, an AWS Config
remediation, a security-team stack — the new
`aws_wafv2_web_acl_association.main` resource will overwrite that association
with no error, and re-assert it on every subsequent plan.

Check first:

```console
aws wafv2 get-web-acl-for-resource --resource-arn <user-pool-arn>
```

If that returns an existing Web ACL that you intend to keep, **import** it
instead of letting Terraform create the association. The import ID is
`WEB_ACL_ARN,RESOURCE_ARN` — comma-separated, no spaces:

```hcl
import {
  to = module.cognito.aws_wafv2_web_acl_association.main
  id = "<web_acl_arn>,<user_pool_arn>"
}
```

The `import` block requires Terraform 1.5+. On older runtimes:

```console
terraform import 'module.cognito.aws_wafv2_web_acl_association.main' \
  '<web_acl_arn>,<user_pool_arn>'
```

If the existing association points at an ACL you are *replacing*, no import is
needed — but confirm that whatever created it will not re-associate its own ACL
later, or the two owners will fight on every apply.

#### 5. Upgrade the provider

The `hashicorp/aws` floor moved to `>= 5.26.0`. If your configuration also uses
`terraform-aws-waf` (floor `>= 6.0`), the resolved version is `>= 6.0`
regardless of what this module asks for.

```console
terraform init -upgrade
```

Commit the resulting `.terraform.lock.hcl` as a **separate commit** from the
functional change, so a provider regression can be bisected independently.

#### 6. Rollback

Pin back to the previous module version and remove `web_acl_arn` from the call.
The association is a standalone resource, so the revert destroys only
`aws_wafv2_web_acl_association.main` — the user pool, its domain, and its
clients are untouched, and no `moved` block is involved.

Rolling back **disassociates the Web ACL**, returning the pool to the Wiz
IDP-007 (`Cognito User Pool WAF should be enabled`) finding state. If you
imported an existing association in step 4, roll back with
`terraform state rm` instead of a destroy, so the pre-existing association
survives.

## 0.1.0

- Initial Cognito module.
- Cognito User Pool.
- Optional Cognito domain.
- Multiple User Pool clients.
- Example implementation.
