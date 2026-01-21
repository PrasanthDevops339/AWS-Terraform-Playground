
#############################################
# Lambda-Based Custom Config Rules
# Tag Value Validation for Backup, EBS, SQS, EFS
#############################################
#
# Purpose:
#   Deploys Lambda-based AWS Config custom rules to enforce
#   organizational tagging standards with complex value validation
#
# Why Lambda over Guard:
#   - Complex business logic (tag value lists from JSON)
#   - Dynamic configuration without code changes
#   - Detailed validation messages
#   - Cross-tag validation logic
#
# Deployment:
#   AFT deploys these to each account during customization phase
#   Lambda functions packaged from modules/scripts/
#
# Resources Created per Rule:
#   - Lambda function (Python 3.12)
#   - Lambda permission (allows Config to invoke)
#   - AWS Config custom rule
#   - CloudWatch log group (30 day retention)
#
# Rules Deployed:
#   1. backup_tags - Backup schedule validation (EC2, RDS, EBS)
#   2. ebs_tags    - EBS volume tag validation
#   3. sqs_tags    - SQS queue tag validation
#   4. efs_tags    - EFS file system tag validation
#
#############################################

#############################################
# Rule 1: Backup Schedule Tag Enforcement
#############################################
# Validates: ops:backupschedule1/2/3 tags
# Resources: EC2 Instances, EBS Volumes, RDS Instances
# Logic: Python script + JSON config

module "backup_tagging_lambda" {
  source = "../../modules/lambda"

  # Environment-specific naming
  workspace              = var.environment
  create_lambda_function = true

  # Lambda configuration
  lambda_name        = "backup_tags"
  lambda_description = "AWS Config custom rule - enforce backup schedule tags"
  runtime            = "python3.12"
  timeout            = 60
  memory_size        = 128

  # Package configuration
  # Zip file created from source_dir containing Python script + JSON config
  package_type = "Zip"
  image_uri     = null
  upload_to_s3  = false
  source_dir    = "${path.module}/../../modules/scripts/backup-tags"

  # CloudWatch Logs configuration
  use_custom_log_group         = false  # Use default log group
  lambda_logs_retention_period = 30     # Days to retain logs
  kms_key_arn                  = var.kms_key_arn  # Optional: encrypt logs

  # IAM permissions required for Lambda function
  # Allows function to report evaluation results back to Config
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

# Lambda permission resource
# Grants AWS Config service permission to invoke the Lambda function
# Without this, Config cannot trigger the function for evaluations
resource "aws_lambda_permission" "allow_config_invoke" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = module.backup_tagging_lambda.lambda_function_name
  principal     = "config.amazonaws.com"  # AWS Config service
}

# AWS Config Custom Rule
# Triggers Lambda function when monitored resources change
resource "aws_config_config_rule" "backup_tagging_rule" {
  name        = "${local.name_prefix}-backup-tagging-enforcement"
  description = "Enforces ops:backupschedule* tags to match approved values"

  # Source configuration - points to our Lambda function
  source {
    owner             = "CUSTOM_LAMBDA"  # Indicates Lambda-based rule
    source_identifier = module.backup_tagging_lambda.lambda_arn

    # Trigger on configuration changes
    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }

  # Resource types to monitor
  # Defined in variables.tf, defaults to EC2, EBS, RDS
  scope {
    compliance_resource_types = var.config_resource_types
  }

  # Ensure permission exists before creating rule
  depends_on = [aws_lambda_permission.allow_config_invoke]
}

#############################################
# Rule 2: EBS Volume Tag Enforcement
#############################################
# Validates: Backup schedules + Environment + Owner tags
# Resources: EBS Volumes only
# Logic: Python script + JSON config

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
