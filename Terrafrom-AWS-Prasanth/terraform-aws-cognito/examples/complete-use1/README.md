# complete-use1 — Cross-Region Example

This is the [`complete`](../complete) example with one difference: the AWS
provider is configured for **us-east-2**, and the module's `region` input puts
every Cognito resource in **us-east-1**.

| Resource | Region |
| --- | --- |
| `aws` provider | `us-east-2` |
| User pool, domain, SAML IdP, app client, WAF association | `us-east-1` |
| Web ACL (`terraform-aws-waf`) | `us-east-1`, via that module's own `region` |

## Why is the provider us-east-2 in a us-east-1 example?

**That mismatch is the test.** The example proves that the module's `region`
input actually moves resources, and it can only prove that if the provider
Region and the target Region disagree.

If the provider were also set to us-east-1, resources would land in us-east-1
whether `region` worked or not — a broken `region` input would pass. Leaving
the provider on us-east-2 means only a working `region` input can produce a
us-east-1 pool, so the `user_pool_region` output is a real assertion rather
than a foregone conclusion.

Do not "fix" the provider to us-east-1. Doing so turns this example into a
duplicate of [`complete`](../complete) that happens to run elsewhere, and
silently removes the only coverage the module has for `region`.

Everything else — the generated self-signed SAML certificate, the placeholder
callback URLs, the schemas — is identical to the complete example. See
[`../complete/README.md`](../complete/README.md) for why the certificate is
generated at apply time and why `samlmetadatafile` is routed through
`local_file.saml_metadata.id`.

## No aliased providers

This example declares exactly one `provider "aws"` block. Both modules take
their own `region` input, so nothing here needs a `providers = { ... }` block
or an alias:

```hcl
module "waf" {
  source = "../../../terraform-aws-waf"
  region = local.target_region
  # ...
}

module "cognitotest" {
  source = "../.."
  region = local.target_region
  # ...
}
```

Removing that boilerplate is the entire point of enhanced region support —
before AWS provider 6.x, this example would have needed a second aliased
provider and a `providers` block on every module call.

Both modules are given the **same** `local.target_region` on purpose. AWS
requires the Web ACL, the user pool, and the association to share a Region, and
the cognito module has a `precondition` that fails the plan if `web_acl_arn`
resolves to a Web ACL somewhere else. Keeping it in one local means the two
inputs cannot drift.

Note that `terraform-aws-waf` resolves `region` through its own
`local.resource_region`, which forces `us-east-1` when `scope = "CLOUDFRONT"`
regardless of what you pass — CloudFront-scope Web ACLs only exist there. This
example uses `scope = "REGIONAL"`, so `region` is honoured as given.

## Run

```bash
terraform init
terraform plan
terraform apply
```

## Validating the result

`terraform apply` prints the check directly:

```hcl
user_pool_region = "us-east-1"
provider_region  = "us-east-2"
```

If `user_pool_region` reads `us-east-2`, the `region` input did not take effect
— check that the AWS provider actually resolved to 6.x, since the resource-level
`region` argument does not exist in 5.x.

Confirm the WAF association landed too:

```bash
aws wafv2 get-web-acl-for-resource \
  --region us-east-1 \
  --resource-arn "$(terraform output -raw user_pool_arn)"
```

## Deploying alongside the complete example

Both examples can run in the same account at the same time. The hosted UI
domain prefix (`testuseast1-<random>` here, `testcomplete-<random>` there) and
the resource names differ, so nothing collides — Cognito prefix domains are
globally unique, which is why the random suffix exists at all.

## Cleanup

```bash
terraform plan -destroy   # review before destroying
terraform destroy
```
