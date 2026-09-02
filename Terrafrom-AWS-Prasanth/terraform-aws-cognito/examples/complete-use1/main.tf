# Cognito prefix domains are globally unique, so the suffix keeps repeated
# applies - and the ../complete example - from colliding.
resource "random_string" "domain_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Same region as the cognito module below: AWS requires the Web ACL, the pool
# and the association to share one.
module "waf" {
  source = "../../../terraform-aws-waf"

  region = local.target_region

  waf_name = "testuseast1"
  scope    = "REGIONAL"
}

# Provider is us-east-2 (version.tf); this `region` input is what moves every
# resource to us-east-1.
module "cognitotest" {
  source = "../.."

  region = local.target_region

  cognito_name = "testuseast1"
  domain_name  = "testuseast1-${random_string.domain_suffix.result}"
  # DO NOT simplify to local_file.saml_metadata.filename - it breaks at plan.
  # See ../complete/main.tf and SELF-SIGNED-SAML-CERT.md section 5.
  samlmetadatafile = local_file.saml_metadata.id == "" ? "" : local_file.saml_metadata.filename
  app_client_name  = "appclienttestuseast1"

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
