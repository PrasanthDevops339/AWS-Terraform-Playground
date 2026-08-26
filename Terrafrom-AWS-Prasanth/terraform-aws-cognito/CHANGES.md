# Mandatory WAF Association — Change Notes (v2.0.0)

## Why this change

Security standard: every Cognito user pool must be WAF-protected. Before
this change, `terraform-aws-cognito` had no way to attach a WAF Web ACL at
all. `aws_cognito_user_pool` has no native `web_acl_arn` argument — the only
way to protect a pool is a separate `aws_wafv2_web_acl_association`
resource, which links a pool ARN to a **REGIONAL**-scope Web ACL ARN in the
same region.

This is a deliberate **breaking change** — existing consumers of this
module must now supply a Web ACL ARN — so the module version bumps to
**2.0.0**.

## What changed

| File | Change |
|---|---|
| `variables.tf` | Added new **required** variable `web_acl_arn` (no default). |
| `main.tf` | Added `resource "aws_wafv2_web_acl_association" "main"`, linking `aws_cognito_user_pool.main.arn` → `var.web_acl_arn`. |
| `versions.tf` | Bumped the `aws` provider constraint from unpinned to `>= 5.26.0`. |
| `examples/complete/main.tf` | Added a `module "waf"` block (source `../../../terraform-aws-waf`, `scope = "REGIONAL"`) and passed `web_acl_arn = module.waf.arn` into `module "cognitotest"`. |
| `CHANGELOG.md` | Added the `## 2.0.0` entry documenting the breaking change. |
| `README.md` | Documented the new required `web_acl_arn` input. |

No resources were renamed (still `main`, not `this`), no Web ACL is created
inside this module, no default was added to `web_acl_arn`, and no
`depends_on` was added between the two modules.

## Why WAF and Cognito are kept decoupled

- **No native attribute to couple them.** `aws_cognito_user_pool` simply
  doesn't have a `web_acl_arn` argument. Association is inherently an
  external, separate resource (`aws_wafv2_web_acl_association`) — there is
  no tighter coupling available even if we wanted one.
- **One Web ACL, many consumers.** Keeping Web ACL creation inside
  `terraform-aws-waf` lets a single, centrally hardened Web ACL be shared
  across multiple Cognito pools (and other regional resources), managed by
  the security team in one place. If `terraform-aws-cognito` created its
  own Web ACL internally (e.g. via a nested `module "waf" {}` call), every
  pool would get its own duplicate ACL, defeating that reuse and putting
  WAF rule ownership inside a module that has nothing to do with WAF
  policy.
- **The mandate is enforced by the variable, not by ownership.** Making
  `web_acl_arn` a **required** variable with no default is what actually
  makes WAF protection mandatory: Terraform refuses to plan or apply the
  cognito module at all until a caller supplies a real Web ACL ARN. That
  achieves the "must be WAF-protected" requirement without hard-coupling
  the two modules together.
- **No `depends_on` needed.** The ARN flows through a normal reference
  chain (`module.waf.arn` → `var.web_acl_arn` → `web_acl_arn` on the
  association resource), which already gives Terraform the correct
  implicit dependency — an explicit `depends_on` between the modules would
  be redundant.

## Consumer impact

Anyone using this module must now also provision (or reference) a
REGIONAL-scope Web ACL and pass its ARN in:

```hcl
module "waf" {
  source = "../../terraform-aws-waf"

  waf_name = "my-app"
  scope    = "REGIONAL"
}

module "cognito" {
  source = "../../terraform-aws-cognito"

  # ...existing required inputs...
  web_acl_arn = module.waf.arn
}
```
