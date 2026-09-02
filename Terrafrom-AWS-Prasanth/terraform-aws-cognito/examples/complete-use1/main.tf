# Cognito hosted-UI prefix domains are globally unique across every AWS
# account, so a hardcoded placeholder collides. The suffix keeps the example
# applyable; the domain itself is never used by anything.
#
# It also has to differ from the complete example's prefix, since both examples
# can be deployed into the same account at the same time.
resource "random_string" "domain_suffix" {
  length  = 8
  special = false
  upper   = false
}

# The Web ACL, the user pool and the association must all share a Region, so
# the WAF module gets the same `region` value as the cognito module below.
# terraform-aws-waf takes its own `region` input, so no aliased provider is
# needed - it resolves this through local.resource_region internally.
module "waf" {
  source = "../../../terraform-aws-waf"

  region = local.target_region

  waf_name = "testuseast1"
  scope    = "REGIONAL"
}

# The provider in version.tf is configured for us-east-2. This single `region`
# input is what puts the user pool, its domain, the SAML IdP, the app client
# and the WAF association in us-east-1 instead - with no aliased provider
# anywhere in this example, which is the point of AWS provider 6.x enhanced
# region support.
module "cognitotest" {
  source = "../.."

  region = local.target_region

  cognito_name = "testuseast1"
  domain_name  = "testuseast1-${random_string.domain_suffix.result}"
  # DO NOT "simplify" this to local_file.saml_metadata.filename.
  #
  # That filename is a statically known string, so it crosses into the module
  # as a plain path with no dependency attached - and the module's
  # `data "local_file"` then reads it at PLAN time, before the file exists:
  #
  #   Error: Read local file data source error
  #   +Original Error: open ./generated/metadata.xml: no such file or directory
  #
  # Routing through .id (known-after-apply) makes the whole expression unknown
  # at plan, so the module defers that read to apply. Unlike `depends_on` on
  # the module call, this defers ONLY the metadata read - the module's
  # aws_caller_identity / aws_iam_account_alias data sources still resolve at
  # plan time, keeping the user pool name and tags visible in the plan.
  #
  # See SELF-SIGNED-SAML-CERT.md section 5, Option B.
  samlmetadatafile = local_file.saml_metadata.id == "" ? "" : local_file.saml_metadata.filename
  app_client_name  = "appclienttestuseast1"

  # Sourced from the us-east-1 Web ACL above. Passing a us-east-2 ARN here
  # fails the module's precondition at plan time rather than at apply.
  web_acl_arn = module.waf.arn

  # Placeholder URLs - no one owns or serves these hosts.
  callback_urls = [
    "https://app.example.com/oauth2/idpresponse"
  ]

  logout_urls = [
    "https://app.example.com/_layouts/SignOut.aspx"
  ]

  deletion_protection = "INACTIVE"

  user_pool_schemas = [
    {
      developer_only_attribute = false
      name                     = "groups"
      data_type                = "String"
      required                 = false
      mutable                  = true
      max_length               = 2048
      min_length               = 0
    },
    {
      developer_only_attribute = false
      name                     = "try1"
      data_type                = "Number"
      required                 = false
      mutable                  = true
      max_value                = 2048
      min_value                = 0
    }
  ]

  extra_attribute_mapping = {
    email              = "mail"
    given_name         = "givenName"
    preferred_username = "userPrincipalName"
  }

  tags = {
    "example" = "Put custom tags here as needed"
    "hello"   = "world"
  }
}
