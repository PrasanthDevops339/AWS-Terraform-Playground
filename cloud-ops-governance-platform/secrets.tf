module "secret_key_db" {
  source   = "tfe.prasanth.com/prasanth/kms/aws"
  key_name = "secret-manager-key"

  key_statements = [
    {
      sid    = "Enable IAM User Permissions"
      effect = "Allow"
      principals = [
        {
          type        = "AWS"
          identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
      ]
      actions   = ["kms:*"]
      resources = ["*"]
    }
  ]
}

module "secrets_manager_service_now_dev" {
  source  = "tfe.prasanth.com/prasanth/secrets-manager/aws"
  version = "1.1.0"

  # Secret
  secret_name              = "Service-Now-Dev-API-Secret"
  description              = "Service Now Dev API cred"
  kms_key_id               = module.service-now-dev-secret-kms.key_arn
  recovery_window_in_days  = 0

  # Policy
  block_public_policy = true
  policy              = data.aws_iam_policy_document.service-now-dev-secret.json

  # Version
  ignore_secret_changes = true

  secret_string = jsonencode({
    CCOP_User = "${var.ServiceNowSecret}"
  })

  # Rotation
  enable_rotation = false
}

module "secrets_manager_splunk_obsrv_dev" {
  source  = "tfe.prasanth.com/prasanth/secrets-manager/aws"
  version = "1.1.0"

  # Secret
  secret_name              = "Splunk-Obsrv-Token"
  description              = "Splunk Obsrv cred"
  kms_key_id               = module.splunk-obsrv-token-kms.key_arn
  recovery_window_in_days  = 0

  # Policy
  block_public_policy = true
  policy              = data.aws_iam_policy_document.splunk-obsrv-token.json

  # Version
  ignore_secret_changes = true

  secret_string = jsonencode({
    obsrv_lambda_token_dev = "${var.ObsrvLambdaToken}"
  })

  # Rotation
  enable_rotation = false
}
