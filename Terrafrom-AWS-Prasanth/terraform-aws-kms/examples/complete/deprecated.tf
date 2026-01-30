# Module version 2.3.11 or below

module "deprecated_complete_primary_key" {
  source = "../../"

  enable_creation = true # Set to false to mark key for deletion
  enable_key      = true # Set to false to disable key

  key_name    = "deprecated-complete-primary-key-${random_string.example_suffix.result}"
  description = "Complete key example showing various configurations available"

  deletion_window_in_days = 8 # Must be between 7 and 30 days (defaults to 7 days)

  key_statements = [
    {
      sid     = "CloudWatchLogs"
      actions = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      resources = ["*"]

      principals = [
        {
          type        = "Service"
          identifiers = ["logs.us-east-2.amazonaws.com"]
        }
      ]

      conditions = [
        {
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:aws:logs:us-east-2:${var.account_id}:log-group:*"]
        }
      ]
    }
  ]

  policy_file = templatefile("./iam/key_policy.json", {
    example_role_arn = data.aws_iam_role.example.arn
  })

  tags = {
    example-tag = "example-value"
  }
}

module "deprecated_complete_replica_key" {
  source = "../../"

  enable_creation = true # Set to false to mark key for deletion
  enable_key      = true # Set to false to disable key
  enable_replica  = true # Must be set to true if creating replica key (defaults to false)

  key_name        = "deprecated-complete-replica-key-${random_string.example_suffix.result}"
  description     = "Complete key replica example showing various configurations available"
  primary_key_arn = module.deprecated_complete_primary_key.key_arn

  deletion_window_in_days = 8 # Must be between 7 and 30 days (defaults to 7 days)

  key_statements = [
    {
      sid     = "CloudWatchLogs"
      actions = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      resources = ["*"]

      principals = [
        {
          type        = "Service"
          identifiers = ["logs.us-east-2.amazonaws.com"]
        }
      ]

      conditions = [
        {
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:aws:logs:us-east-2:${var.account_id}:log-group:*"]
        }
      ]
    }
  ]

  policy_file = templatefile("./iam/key_policy.json", {
    example_role_arn = data.aws_iam_role.example.arn
  })

  tags = {
    example-tag = "example-value-replica"
  }

  # Must provide a secondary region for replica key
  providers = {
    aws = aws.us_east_1
  }
}
