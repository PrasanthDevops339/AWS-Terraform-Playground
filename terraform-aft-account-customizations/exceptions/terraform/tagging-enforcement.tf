
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

#############################################
# EBS Volume Tagging Enforcement
#############################################

module "ebs_tagging_lambda" {
  source = "../../modules/lambda"

  workspace              = var.environment
  create_lambda_function = true

  lambda_name        = "ebs_tags"
  lambda_description = "AWS Config custom rule - enforce EBS volume tags"
  runtime            = "python3.12"
  timeout            = 60
  memory_size        = 128

  package_type = "Zip"
  image_uri     = null
  upload_to_s3  = false
  source_dir    = "${path.module}/../../modules/scripts/ebs-tags"

  use_custom_log_group         = false
  lambda_logs_retention_period = 30
  kms_key_arn                  = var.kms_key_arn

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

resource "aws_lambda_permission" "allow_config_invoke_ebs" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = module.ebs_tagging_lambda.lambda_function_name
  principal     = "config.amazonaws.com"
}

resource "aws_config_config_rule" "ebs_tagging_rule" {
  name        = "${local.name_prefix}-ebs-tagging-enforcement"
  description = "Enforces required tags on EBS volumes"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = module.ebs_tagging_lambda.lambda_arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }

  scope {
    compliance_resource_types = ["AWS::EC2::Volume"]
  }

  depends_on = [aws_lambda_permission.allow_config_invoke_ebs]
}

#############################################
# SQS Queue Tagging Enforcement
#############################################

module "sqs_tagging_lambda" {
  source = "../../modules/lambda"

  workspace              = var.environment
  create_lambda_function = true

  lambda_name        = "sqs_tags"
  lambda_description = "AWS Config custom rule - enforce SQS queue tags"
  runtime            = "python3.12"
  timeout            = 60
  memory_size        = 128

  package_type = "Zip"
  image_uri     = null
  upload_to_s3  = false
  source_dir    = "${path.module}/../../modules/scripts/sqs-tags"

  use_custom_log_group         = false
  lambda_logs_retention_period = 30
  kms_key_arn                  = var.kms_key_arn

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

resource "aws_lambda_permission" "allow_config_invoke_sqs" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = module.sqs_tagging_lambda.lambda_function_name
  principal     = "config.amazonaws.com"
}

resource "aws_config_config_rule" "sqs_tagging_rule" {
  name        = "${local.name_prefix}-sqs-tagging-enforcement"
  description = "Enforces required tags on SQS queues"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = module.sqs_tagging_lambda.lambda_arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }

  scope {
    compliance_resource_types = ["AWS::SQS::Queue"]
  }

  depends_on = [aws_lambda_permission.allow_config_invoke_sqs]
}

#############################################
# EFS File System Tagging Enforcement
#############################################

module "efs_tagging_lambda" {
  source = "../../modules/lambda"

  workspace              = var.environment
  create_lambda_function = true

  lambda_name        = "efs_tags"
  lambda_description = "AWS Config custom rule - enforce EFS file system tags"
  runtime            = "python3.12"
  timeout            = 60
  memory_size        = 128

  package_type = "Zip"
  image_uri     = null
  upload_to_s3  = false
  source_dir    = "${path.module}/../../modules/scripts/efs-tags"

  use_custom_log_group         = false
  lambda_logs_retention_period = 30
  kms_key_arn                  = var.kms_key_arn

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

resource "aws_lambda_permission" "allow_config_invoke_efs" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = module.efs_tagging_lambda.lambda_function_name
  principal     = "config.amazonaws.com"
}

resource "aws_config_config_rule" "efs_tagging_rule" {
  name        = "${local.name_prefix}-efs-tagging-enforcement"
  description = "Enforces required tags on EFS file systems"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = module.efs_tagging_lambda.lambda_arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }

  scope {
    compliance_resource_types = ["AWS::EFS::FileSystem"]
  }

  depends_on = [aws_lambda_permission.allow_config_invoke_efs]
}

#############################################
# Guard Policy Rules Conformance Pack
#############################################

module "policy_rules_conformance_pack" {
  source = "../../modules/conformance_pack"

  cpack_name        = "resource-validation-pack"
  organization_pack = false  # Set to true for org-wide deployment
  random_id         = null

  policy_rules_list = [
    {
      config_rule_name     = "ebs-validation"
      config_rule_version  = "2026-01-21"
      description          = "Validates EBS encryption and required tags"
      resource_types_scope = ["AWS::EC2::Volume", "AWS::EC2::Snapshot"]
    },
    {
      config_rule_name     = "sqs-validation"
      config_rule_version  = "2026-01-21"
      description          = "Validates SQS encryption and required tags"
      resource_types_scope = ["AWS::SQS::Queue"]
    },
    {
      config_rule_name     = "efs-validation"
      config_rule_version  = "2026-01-21"
      description          = "Validates EFS encryption, performance mode, and required tags"
      resource_types_scope = ["AWS::EFS::FileSystem"]
    }
  ]

  tags = var.tags
}
