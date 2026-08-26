module "waf" {
  source = "../../../terraform-aws-waf"

  waf_name = "testcomplete"
  scope    = "REGIONAL"
}

module "cognitotest" {
  source = "../.."

  cognito_name     = "testcomplete"
  domain_name      = "prasantestcomplete"
  samlmetadatafile = "${path.module}/files/metadata.xml"
  app_client_name  = "appclienttestcomplete"
  web_acl_arn      = module.waf.arn

  callback_urls = [
    "https://prasa-dev-test.prasanth.com/oauth2/idpresponse"
  ]

  logout_urls = [
    "https://testportal.prasanth.com/_layouts/SignOut.aspx"
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
