###############################################################################
# us-east-1 deployment
#
# main.tf sets no `region`, so its pool follows the provider (us-east-2). This
# file sets `region` explicitly, putting a second pool in us-east-1 from the
# same single provider configuration - no aliased provider anywhere.
#
# Applying this directory therefore proves both paths at once: region-unset
# stays put, region-set moves.
###############################################################################

locals {
  # One value, both module calls. AWS requires the Web ACL, the pool and the
  # association to share a Region, so these must never drift.
  # The cognito module only accepts null, "us-east-1" or "us-east-2".
  use1_region = "us-east-1"
}

resource "random_string" "domain_suffix_use1" {
  length  = 8
  special = false
  upper   = false
}

module "waf_use1" {
  source = "../../../terraform-aws-waf"

  region = local.use1_region

  waf_name                   = "testcomplete-use1"
  scope                      = "REGIONAL"
  create_ip_set              = false
  cloudwatch_metrics_enabled = true
  sampled_requests_enabled   = true
}

module "cognitotest_use1" {
  source = "../.."

  region = local.use1_region

  cognito_name = "testcompleteuse1"
  domain_name  = "testcompleteuse1-${random_string.domain_suffix_use1.result}"

  # #########################################################################
  # EXAMPLE ONLY - DO NOT COPY THIS LINE INTO APPLICATION CODE.
  # Same throwaway self-signed SAML metadata as the us-east-2 pool - see
  # saml.tf. Application code points `samlmetadatafile` directly at the
  # metadata file its real IdP issued, with no generation step.
  # #########################################################################
  #
  # The `.id` routing is load-bearing; see the note in main.tf before changing it.
  samlmetadatafile = local_file.saml_metadata.id == "" ? "" : local_file.saml_metadata.filename
  app_client_name  = "appclienttestcompleteuse1"
  web_acl_arn      = module.waf_use1.arn

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

output "user_pool_arn_use1" {
  description = "ARN of the us-east-1 user pool."
  value       = module.cognitotest_use1.aws_cognito_user_pool_arn
}

output "user_pool_region_use1" {
  description = "Region of the us-east-1 pool. Must read us-east-1, NOT the provider's us-east-2 - that difference is the proof `region` works."
  value       = provider::aws::arn_parse(module.cognitotest_use1.aws_cognito_user_pool_arn).region
}

output "web_acl_arn_use1" {
  description = "ARN of the us-east-1 Web ACL. Its Region must match user_pool_region_use1."
  value       = module.waf_use1.arn
}
