#########################
# examples/complete/kms.tf
#########################

module "kms" {
  source          = "tfe.com/kms/aws"
  enable_creation = true
  enable_key      = true
  key_name        = "${local.account_alias}-ecs-logs-key-complete"
  description     = "Key for encryption of ecs cluster logs"

  key_statements = [
    {
      sid    = "CloudWatchLogs"
      effect = "Allow"
      principals = [{
        type        = "Service"
        identifiers = ["logs.us-east-2.amazonaws.com"]
      }]
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources  = ["*"]
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:us-east-2:${data.aws_caller_identity.current.account_id}:*"]
      }]
    }
  ]
}
