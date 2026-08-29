variable "cognito_name" {
  description = "(Required) Name of the user pool"
  type        = string
}

variable "domain_name" {
  description = "(Required) For custom domains, this is the fully-qualified domain name, such as auth.example.com. For Amazon Cognito prefix domains, this is the prefix alone, such as auth."
  type        = string
}

variable "allowed_oauth_flows_user_pool_client" {
  type    = bool
  default = true
}

variable "case_sensitive" {
  description = "(Required) Whether username case sensitivity will be applied for all users in the user pool through Cognito APIs"
  type        = bool
  default     = false
}

variable "mfa_configuration" {
  description = "Multi-Factor Authentication (MFA) configuration for the User Pool"
  type        = string
  default     = "ON"
}

variable "software_token_mfa_configuration" {
  description = "Boolean whether to enable software token Multi-Factor (MFA) tokens, such as Time-based One-Time Password (TOTP). To disable software token MFA when sms_configuration is not present, the mfa_configuration argument must be set to OFF and the software_token_mfa_configuration configuration block must be fully removed."
  type        = bool
  default     = true
}

variable "account_recovery_setting_name" {
  description = "Recovery method for a user. Can be of the following"
  type        = string
  default     = "admin_only"
}

variable "account_recovery_setting_priority" {
  description = "Positive integer specifying priority of a method with 1 being the highest priority."
  type        = number
  default     = 1
}

variable "email_sending_account" {
  description = "Email delivery method to use. COGNITO_DEFAULT for the default email functionality built into Cognito or DEVELOPER to use your Amazon SES configuration"
  type        = string
  default     = "COGNITO_DEFAULT"
}

variable "advanced_security_mode" {
  description = "Mode for advanced security"
  type        = string
  default     = "OFF"
}

variable "provider_name" {
  description = "The provider name"
  type        = string
  default     = "prasa-federate-idp"
}

variable "samlmetadatafile" {
  description = "Path to the SAML metadata file. Give the exact path to your metadata file. Leave null when supplying `saml_metadata_content` instead."
  type        = string
  default     = null

  validation {
    condition     = (var.samlmetadatafile == null) != (var.saml_metadata_content == null)
    error_message = "Set exactly one of samlmetadatafile or saml_metadata_content."
  }
}

variable "saml_metadata_content" {
  description = "SAML metadata XML passed inline instead of read from disk. Useful when the metadata is generated during the run (for example a self-signed signing certificate in an example or test)."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "When active, DeletionProtection prevents accidental deletion of your user pool."
  type        = string
  default     = "ACTIVE"
}

variable "tags" {
  description = "Default tag values to be applied to all resources"
  type        = map(string)
  default     = {}
}

variable "app_client_name" {
  description = "Name of the application client"
  type        = string
}

variable "generate_secret" {
  description = "Should an application secret be generated"
  type        = bool
  default     = true
}

variable "explicit_auth_flows" {
  description = "List of authentication flows"
  type        = set(string)
  default     = ["ALLOW_USER_SRP_AUTH"]
}

variable "enable_token_revocation" {
  description = "Enables or disables token revocation"
  type        = bool
  default     = true
}

variable "prevent_user_existence_errors" {
  description = "Choose which errors and responses are returned by Cognito APIs during authentication, account confirmation, and password recovery when the user does not exist in the user pool"
  type        = string
  default     = "ENABLED"
}

variable "auth_session_validity" {
  description = "Amazon Cognito creates a session token for each API request in an authentication flow."
  type        = number
  default     = 3
}

variable "refresh_token_validity" {
  description = "Time limit, between 60 minutes and 10 years, after which the refresh token is no longer valid and cannot be used"
  type        = number
  default     = 90
}

variable "access_token_validity" {
  description = "Time limit, between 5 minutes and 1 day, after which the access token is no longer valid and cannot be used."
  type        = number
  default     = 15
}

variable "id_token_validity" {
  description = "Time limit, between 5 minutes and 1 day, after which the ID token is no longer valid and cannot be used"
  type        = number
  default     = 15
}

variable "refresh_token_rotation" {
  description = "The state of refresh token rotation for the current app client"
  type        = string
  default     = "ENABLED"
}

variable "retry_grace_period_seconds" {
  description = "Time period, between 0 and 60 seconds, that a user has to use the old refresh token before it is invalidated"
  type        = number
  default     = 0
}

variable "callback_urls" {
  description = "List of allowed callback URLs for the identity providers."
  type        = set(string)
}

variable "logout_urls" {
  description = "(Optional)List of allowed logout URLs for the identity providers. allowed_oauth_flows_user_pool_client must be set to true before you can configure this option."
  type        = list(string)
  default     = []
}

variable "supported_identity_providers" {
  description = "List of provider names for the identity providers that are supported on this client."
  type        = set(string)
  default     = ["prasa-federate-idp"]
}

variable "allowed_oauth_flows" {
  description = "List of allowed OAuth flows (code, implicit, client_credentials"
  type        = set(string)
  default     = ["code"]
}

variable "allowed_oauth_scopes" {
  description = "List of allowed OAuth scopes"
  type        = set(string)
  default     = ["openid"]
}

variable "user_pool_schemas" {
  description = "List of custom attributes for cognito user pool"
  type = list(object({
    developer_only_attribute = bool
    name                     = string
    data_type                = string
    required                 = bool
    mutable                  = bool
    min_length               = optional(number)
    max_length               = optional(number)
    min_value                = optional(number)
    max_value                = optional(number)
  }))
  default = [{
    developer_only_attribute = false
    name                     = "groups"
    data_type                = "String"
    required                 = false
    mutable                  = true
    max_length               = 2048
    min_length               = 0
  }]
}

variable "web_acl_arn" {
  description = "(Required) ARN of a REGIONAL-scope AWS WAFv2 Web ACL to associate with the Cognito User Pool. Every user pool must be WAF-protected."
  type        = string
}

variable "extra_attribute_mapping" {
  description = "Additional attribute mappings for Cognito IdP"
  type        = map(string)
  default     = {}

  validation {
    condition = length(
      setintersection(
        keys(var.extra_attribute_mapping),
        ["username", "custom:groups"]
      )
    ) == 0
    error_message = "extra_attribute_mapping cannot override default keys username and custom:groups"
  }
}
