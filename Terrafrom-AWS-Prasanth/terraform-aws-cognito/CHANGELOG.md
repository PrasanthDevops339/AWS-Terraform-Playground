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
