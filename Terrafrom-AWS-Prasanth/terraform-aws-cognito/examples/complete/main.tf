# Cognito hosted-UI prefix domains are globally unique across every AWS
# account, so a hardcoded placeholder collides. The suffix keeps the example
# applyable; the domain itself is never used by anything.
resource "random_string" "domain_suffix" {
  length  = 8
  special = false
  upper   = false
}

module "waf" {
  source = "../../../terraform-aws-waf"

  waf_name                   = "testcomplete"
  scope                      = "REGIONAL"
  create_ip_set              = false
  cloudwatch_metrics_enabled = true
  sampled_requests_enabled   = true
}

# No `region` input on purpose - this pool lands in the provider's us-east-2.
# main-use1.tf is the same call with region set, landing in us-east-1.
module "cognitotest" {
  source = "../.."

  cognito_name = "testcomplete"
  domain_name  = "testcomplete-${random_string.domain_suffix.result}"
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
  app_client_name  = "appclienttestcomplete"
  web_acl_arn      = module.waf.arn

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
