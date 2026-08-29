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

  waf_name = "testcomplete"
  scope    = "REGIONAL"
}

module "cognitotest" {
  source = "../.."

  cognito_name          = "testcomplete"
  domain_name           = "testcomplete-${random_string.domain_suffix.result}"
  saml_metadata_content = local.saml_metadata
  app_client_name       = "appclienttestcomplete"
  web_acl_arn           = module.waf.arn

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
