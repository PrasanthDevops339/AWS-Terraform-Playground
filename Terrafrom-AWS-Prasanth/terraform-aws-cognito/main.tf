locals {
  account_alias = data.aws_iam_account_alias.current.account_alias

  # Region the resources actually land in. Used by the WAF preconditions only.
  effective_region = data.aws_region.current.region

  # Named ARN fields for the WAF preconditions. arn_parse errors on a malformed
  # ARN, so a bad web_acl_arn fails here rather than silently mis-parsing.
  web_acl = provider::aws::arn_parse(var.web_acl_arn)

  base_attribute_mapping = {
    "username"      = "SAMLAccountName"
    "custom:groups" = "groups"
  }
}

resource "aws_cognito_user_pool" "main" {
  region = var.region

  name = "${local.account_alias}-${var.cognito_name}"

  username_configuration {
    case_sensitive = var.case_sensitive
  }

  ###### User account recovery
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 99
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }

  ######## MFA

  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = var.software_token_mfa_configuration
  }

  ######## Self-service sign-up
  account_recovery_setting {
    recovery_mechanism {
      name     = var.account_recovery_setting_name
      priority = var.account_recovery_setting_priority
    }
  }

  ######## Required attributes & Custom attributes
  dynamic "schema" {
    for_each = var.user_pool_schemas == null ? [] : var.user_pool_schemas
    content {
      attribute_data_type      = schema.value.data_type
      developer_only_attribute = schema.value.developer_only_attribute
      mutable                  = schema.value.mutable
      name                     = schema.value.name
      required                 = schema.value.required

      dynamic "string_attribute_constraints" {
        for_each = schema.value.data_type == "String" ? [1] : []
        content {
          min_length = try(schema.value.min_length, null)
          max_length = try(schema.value.max_length, null)
        }
      }

      dynamic "number_attribute_constraints" {
        for_each = schema.value.data_type == "Number" ? [1] : []
        content {
          min_value = try(schema.value.min_value, null)
          max_value = try(schema.value.max_value, null)
        }
      }
    }
  }

  ######## Configure message delivery
  email_configuration {
    email_sending_account = var.email_sending_account
  }

  #### Advanced Security
  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }

  ###Deletion Protection

  deletion_protection = var.deletion_protection
  tags                = merge(var.tags, { "Name" = "${local.account_alias}-${var.cognito_name}" }, local.platform_tags)
}

######## Creating domain

resource "aws_cognito_user_pool_domain" "main" {
  region = var.region

  domain       = var.domain_name
  user_pool_id = aws_cognito_user_pool.main.id
}

###### Creating IDP

resource "aws_cognito_identity_provider" "main" {
  region = var.region

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = var.provider_name
  provider_type = "SAML"

  provider_details = {
    MetadataFile = data.local_file.saml_metadata.content
  }

  attribute_mapping = merge(
    local.base_attribute_mapping,
    var.extra_attribute_mapping,
  )
}

resource "aws_cognito_user_pool_client" "main" {
  region = var.region

  name                                 = var.app_client_name
  user_pool_id                         = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = var.allowed_oauth_flows_user_pool_client
  generate_secret                      = var.generate_secret
  explicit_auth_flows                  = var.explicit_auth_flows
  enable_token_revocation              = var.enable_token_revocation
  prevent_user_existence_errors        = var.prevent_user_existence_errors
  auth_session_validity                = var.auth_session_validity
  refresh_token_validity               = var.refresh_token_validity
  access_token_validity                = var.access_token_validity
  id_token_validity                    = var.id_token_validity
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  supported_identity_providers         = var.supported_identity_providers
  allowed_oauth_flows                  = var.allowed_oauth_flows
  allowed_oauth_scopes                 = var.allowed_oauth_scopes

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "minutes"
  }

  refresh_token_rotation {
    feature                    = var.refresh_token_rotation
    retry_grace_period_seconds = var.retry_grace_period_seconds
  }

  depends_on = [
    aws_cognito_user_pool.main,
    aws_cognito_identity_provider.main
  ]
}

###### WAF Association

resource "aws_wafv2_web_acl_association" "main" {
  region = var.region

  resource_arn = aws_cognito_user_pool.main.arn
  web_acl_arn  = var.web_acl_arn

  # A mismatched Web ACL fails at apply with an opaque AWS error; catch it here.
  lifecycle {
    precondition {
      condition     = local.web_acl.service == "wafv2"
      error_message = "web_acl_arn must be a WAFv2 Web ACL ARN; got a '${local.web_acl.service}' ARN: '${var.web_acl_arn}'."
    }

    # WAFv2 encodes scope in the resource path: "regional/..." or "global/...".
    precondition {
      condition     = startswith(local.web_acl.resource, "regional/")
      error_message = "web_acl_arn must be a REGIONAL-scope Web ACL; got '${var.web_acl_arn}'. A CLOUDFRONT-scope Web ACL cannot be associated with a Cognito User Pool. Set scope = \"REGIONAL\" on the WAF module."
    }

    # Compared against effective_region, not var.region: terraform-aws-waf has
    # its own `region`, so the ACL can move while var.region here stays null.
    precondition {
      condition     = local.web_acl.region == local.effective_region
      error_message = "web_acl_arn is a Web ACL in ${local.web_acl.region}, but this module's resources are in ${local.effective_region}. The Web ACL, the user pool, and the association must all be in the same Region - pass the same region value to the WAF module and to this one."
    }
  }
}
