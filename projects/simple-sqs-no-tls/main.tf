###############################################################################
# Simple SQS Deployment — No SecureTransport Policy
#
# This configuration deploys:
# - KMS key for SQS encryption at rest
# - SQS queue (main) with KMS encryption
# - SQS dead letter queue
#
# SecureTransport enforcement is intentionally OFF here.
# Use simple-sqs-with-tls to test the effect of enabling it.
###############################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
    }
  )
}

###############################################################################
# KMS Key for SQS Encryption at Rest
###############################################################################

module "kms" {
  source = "../../Terrafrom-AWS-Prasanth/terraform-aws-kms"

  enable_creation         = true
  enable_key              = true
  key_name                = "${local.name_prefix}-sqs-key"
  description             = "KMS key for SQS encryption at rest - ${local.name_prefix}"
  deletion_window_in_days = 7

  key_statements = [
    {
      sid    = "SQSServicePermissions"
      effect = "Allow"

      principals = [{
        type        = "Service"
        identifiers = ["sqs.amazonaws.com"]
      }]

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]

      resources = ["*"]

      conditions = [{
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }]
    }
  ]

  tags = local.common_tags
}

###############################################################################
# SQS Queue — SecureTransport NOT enforced
###############################################################################

module "sqs" {
  source = "../../Terrafrom-AWS-Prasanth/terraform-aws-sqs"

  queue_name = "${local.name_prefix}-orders"

  # Queue behaviour defaults (tune per workload)
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600  # 4 days
  receive_wait_time_seconds  = 20      # long polling — saves cost
  max_message_size           = 262144  # 256 KB

  # Encryption at rest via KMS
  kms_master_key_id                 = module.kms.key_arn
  kms_data_key_reuse_period_seconds = 300

  # Dead letter queue for poison-pill messages
  enable_dlq                    = true
  dlq_message_retention_seconds = 1209600 # 14 days
  max_receive_count             = 3

  # SecureTransport enforcement — OFF for baseline testing
  # Flip to true in simple-sqs-with-tls to verify nothing breaks
  enable_secure_transport = false

  tags = local.common_tags
}

