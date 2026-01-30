# Module version 3.0.0 or higher

resource "random_string" "example_suffix" {
  length  = 6
  numeric = false
  special = false
  upper   = false
}

module "complete_multi_region_key" {
  source = "../../"

  enable_creation        = true
  enable_key             = true
  enable_replica         = true
  enable_region_argument = true

  key_name         = "complete-primary-key-${random_string.example_suffix.result}"
  replica_key_name = "complete-secondary-key-${random_string.example_suffix.result}"
  description      = "Complete key example showing various configurations available"

  deletion_window_in_days = 7

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

  replica_key_statements = [
    {
      sid     = "CloudWatchLogsReplica"
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

  replica_policy_file = templatefile("./iam/replica_key_policy.json", {
    example_role_arn = data.aws_iam_role.example.arn
  })

  tags = {
    example-tag = "example-value"
  }
}
