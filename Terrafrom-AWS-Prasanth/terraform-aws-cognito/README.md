# terraform-aws-cognito

Reusable Terraform module for provisioning an Amazon Cognito User Pool, optional hosted UI domain, and one or more User Pool clients.

## Example

```hcl
module "cognito" {
  source = "../../"

  name   = "sample-app-users"
  domain = "sample-app-users"

  web_acl_arn = module.waf.arn

  clients = {
    web = {
      callback_urls = ["https://app.example.com/callback"]
      logout_urls   = ["https://app.example.com/logout"]
    }
  }

  tags = {
    environment = "dev"
    application = "sample-app"
  }
}
```

## Requirements

- AWS provider **>= 6.0.0**. The module sets the resource-level `region`
  argument, which is 6.x only.
- Terraform **>= 1.8**, for the provider-defined function
  `provider::aws::arn_parse` used by the WAF preconditions.

## Inputs

- `web_acl_arn` (required) — ARN of a REGIONAL-scope AWS WAFv2 Web ACL, in
  the same region as the user pool, to associate via
  `aws_wafv2_web_acl_association`. Every user pool must be WAF-protected;
  there is no default. Source this from a shared `terraform-aws-waf` module
  instance's `arn` output.
- `region` (optional, default `null`) — AWS Region for the module's regional
  resources. When `null`, every resource uses the Region configured on the
  `aws` provider, which is the pre-existing behaviour. Set it to deploy the
  pool outside the provider's Region without declaring an aliased provider.

  **Allowed values: `null`, `"us-east-1"`, `"us-east-2"`.** A `validation`
  block rejects anything else at plan time. This is an allow-list of the
  Regions this platform deploys into, not an AWS limitation — widen the
  `contains([...])` list in `variables.tf` when a new Region is approved.

  Note the allow-list constrains `region` only. It does not constrain the
  Region the `aws` provider is configured for, so leaving `region` null in a
  provider configured for some other Region still works.

### Deploying to a non-default Region

```hcl
provider "aws" {
  region = "us-east-2"
}

module "cognito" {
  source = "tfe.example.com/org/cognito/aws"

  region = "us-east-1" # pool, domain, IdP, client and WAF association

  # ...existing required inputs...
}
```

`region` is applied to `aws_cognito_user_pool`, `aws_cognito_user_pool_domain`,
`aws_cognito_identity_provider`, `aws_cognito_user_pool_client` and
`aws_wafv2_web_acl_association`. It is deliberately **not** applied to the
`aws_caller_identity` or `aws_iam_account_alias` data sources — IAM and STS are
global services that the AWS provider excludes from enhanced region support.

**The Web ACL must be a REGIONAL-scope WAFv2 ACL in the same Region.** Three
`precondition` blocks on the association enforce this at plan time rather than
letting it surface as an opaque apply-time AWS error:

- the ARN must be a `wafv2` ARN — an ALB ARN passed by mistake is rejected;
- the Web ACL must be REGIONAL-scope. A CLOUDFRONT-scope ACL cannot be
  associated with a user pool, and `terraform-aws-waf` places CLOUDFRONT ACLs
  in us-east-1, so scope is checked separately from Region;
- the Web ACL's Region must equal the Region this module's resources land in —
  `region` when set, the provider's Region when not.

All three read named fields from `provider::aws::arn_parse`, so they do not
depend on ARN field ordering and fail cleanly on a malformed ARN.

This matters because **both modules take independent `region` inputs**: moving
one without the other is now possible in either direction, including leaving
`region` unset here while the WAF module is given one.

`terraform-aws-waf` takes its own `region` input, so pass the same value to
both modules and no aliased provider is needed anywhere:

```hcl
module "waf" {
  source = "tfe.example.com/org/waf/aws"
  region = "us-east-1"
  scope  = "REGIONAL"
  # ...
}

module "cognito" {
  source      = "tfe.example.com/org/cognito/aws"
  region      = "us-east-1"
  web_acl_arn = module.waf.arn
  # ...
}
```

[`examples/complete`](examples/complete) shows this in full, in `main-use1.tf`.

## Examples

A single example, [`complete`](examples/complete), deploys the module twice
from one provider configuration:

| File | Provider Region | `region` input | Resource Region |
| --- | --- | --- | --- |
| `main.tf` | us-east-2 | not set | us-east-2 |
| `main-use1.tf` | us-east-2 | `"us-east-1"` | us-east-1 |

## Outputs

- `user_pool_id`
- `user_pool_arn`
- `user_pool_endpoint`
- `client_ids`
- `domain`
