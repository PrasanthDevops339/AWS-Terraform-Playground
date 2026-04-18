########################################
# examples/complete/cloudwatch.tf
#
# Per-tier CloudWatch log groups (encrypted via KMS)
# + SNS topic for CloudWatch alarm notifications
########################################

########################################
# KMS key — log group encryption
########################################

module "kms" {
  source = "tfe.com/kms/aws"

  enable_creation         = true
  enable_key              = true
  key_name                = "${var.environment}-ecs-logs-kms"
  description             = "KMS key for ECS CloudWatch log groups and ECS Exec"
  deletion_window_in_days = 14

  key_statements = [
    {
      sid    = "CloudWatchLogs"
      effect = "Allow"
      principals = [{
        type        = "Service"
        identifiers = ["logs.amazonaws.com"]
      }]
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  ]

  tags = var.tags
}

########################################
# Per-tier log groups
########################################

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.environment}/frontend"
  retention_in_days = 30
  kms_key_id        = module.kms.key_arn
  tags              = merge(var.tags, { tier = "frontend" })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.environment}/api"
  retention_in_days = 30
  kms_key_id        = module.kms.key_arn
  tags              = merge(var.tags, { tier = "api" })
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.environment}/worker"
  retention_in_days = 14
  kms_key_id        = module.kms.key_arn
  tags              = merge(var.tags, { tier = "worker" })
}

resource "aws_cloudwatch_log_group" "exec_logs" {
  name              = "/ecs/${var.environment}/exec-logs"
  retention_in_days = 90
  kms_key_id        = module.kms.key_arn
  tags              = merge(var.tags, { purpose = "ecs-exec" })
}

########################################
# SNS topic — CloudWatch alarm notifications
########################################

module "alerts" {
  source = "tfe.com/sns/aws"

  name         = "${var.environment}-ecs-alerts"
  display_name = "${var.environment} ECS Alerts"
  tags         = var.tags

  # Add subscriber email via tfvars or a separate aws_sns_topic_subscription resource
}
