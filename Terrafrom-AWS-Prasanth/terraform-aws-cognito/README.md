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

## Inputs

- `web_acl_arn` (required) — ARN of a REGIONAL-scope AWS WAFv2 Web ACL, in
  the same region as the user pool, to associate via
  `aws_wafv2_web_acl_association`. Every user pool must be WAF-protected;
  there is no default. Source this from a shared `terraform-aws-waf` module
  instance's `arn` output.

## Outputs

- `user_pool_id`
- `user_pool_arn`
- `user_pool_endpoint`
- `client_ids`
- `domain`
