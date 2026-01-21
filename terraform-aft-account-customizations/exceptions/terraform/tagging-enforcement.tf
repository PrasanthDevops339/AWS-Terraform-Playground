
#############################################
# Tagging Enforcement (Backup schedule tags)
#############################################

module "backup_tagging_lambda" {
  source = "../../modules/lambda"

  workspace              = var.environment
  create_lambda_function = true

  lambda_name        = "backup_tags"
  lambda_description = "AWS Config custom rule - enforce backup schedule tags"
  runtime            = "python3.12"
  timeout            = 60
  memory_size        = 128

  # Package from repo folder
  package_type = "Zip"
  image_uri     = null
  upload_to_s3  = false
  source_dir    = "${path.module}/../../modules/scripts/backup-tags"

  # Logging
  use_custom_log_group         = false
  lambda_logs_retention_period = 30
  kms_key_arn                  = var.kms_key_arn

  # IAM permissions for Config evaluation
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConfigPutEvaluations"
        Effect = "Allow"
        Action = [
          "config:PutEvaluations"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Allow AWS Config to invoke the Lambda
resource "aws_lambda_permission" "allow_config_invoke" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = module.backup_tagging_lambda.lambda_function_name
  principal     = "config.amazonaws.com"
}

# AWS Config Custom Rule
resource "aws_config_config_rule" "backup_tagging_rule" {
  name        = "${local.name_prefix}-backup-tagging-enforcement"
  description = "Enforces ops:backupschedule* tags to match approved values"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = module.backup_tagging_lambda.lambda_arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }

  scope {
    compliance_resource_types = var.config_resource_types
  }

  depends_on = [aws_lambda_permission.allow_config_invoke]
}
