# Changelog

## 2.0.0

- **Breaking:** `web_acl_arn` is now a required variable (no default). Every
  Cognito User Pool created by this module must be associated with a
  REGIONAL-scope AWS WAFv2 Web ACL, via a new `aws_wafv2_web_acl_association.main`
  resource.
- **Breaking:** minimum `hashicorp/aws` provider version raised to `>= 5.26.0`.
- Consumers should source the Web ACL from a shared `terraform-aws-waf`
  module instance and pass its `arn` output in as `web_acl_arn`.

## 0.1.0

- Initial Cognito module.
- Cognito User Pool.
- Optional Cognito domain.
- Multiple User Pool clients.
- Example implementation.
