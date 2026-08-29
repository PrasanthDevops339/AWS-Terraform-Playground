# Changelog

## 2.1.0

- Added `saml_metadata_content`, an optional input that accepts the SAML
  metadata XML inline instead of reading it from disk. Exactly one of
  `saml_metadata_content` or `samlmetadatafile` must be set; `samlmetadatafile`
  now defaults to `null` and is otherwise unchanged, so existing callers are
  unaffected.
- Declared the implicit `hashicorp/local` provider dependency and added
  `required_version = ">= 1.3"`.
- The complete example no longer ships a static `files/metadata.xml` whose
  signing certificate had expired. It now generates a throwaway self-signed
  certificate with the `hashicorp/tls` provider and renders the metadata around
  it, and suffixes the hosted UI domain prefix with a random string so repeated
  applies do not collide on the globally unique namespace.

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
