###############################################################################
# Locals
###############################################################################

locals {
  account_alias = data.aws_iam_account_alias.current.account_alias

  queue_full_name = "${local.account_alias}-${var.queue_name}"
  dlq_full_name   = "${local.account_alias}-${var.queue_name}-dlq"

  merged_tags = merge(local.platform_tags, var.tags)

  # Redrive policy JSON — only used when DLQ is enabled
  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  # Attach a queue policy only when secure transport enforcement is requested
  attach_policy = var.enable_secure_transport
}

###############################################################################
# Dead Letter Queue (optional)
###############################################################################

resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = local.dlq_full_name
  message_retention_seconds = var.dlq_message_retention_seconds

  # Mirror the same at-rest encryption as the main queue
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_master_key_id != null ? var.kms_data_key_reuse_period_seconds : null

  tags = merge(
    local.merged_tags,
    { Name = local.dlq_full_name }
  )
}

###############################################################################
# Main SQS Queue
###############################################################################

resource "aws_sqs_queue" "main" {
  name                       = local.queue_full_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  max_message_size           = var.max_message_size
  delay_seconds              = var.delay_seconds

  # Encryption at rest
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_master_key_id != null ? var.kms_data_key_reuse_period_seconds : null

  # Redrive to DLQ when enabled
  redrive_policy = local.redrive_policy

  tags = merge(
    local.merged_tags,
    { Name = local.queue_full_name }
  )
}

###############################################################################
# Queue Policy — SecureTransport enforcement
#
# This deny is a governance guardrail. In practice, SQS public endpoints only
# accept HTTPS, so standard AWS SDK/CLI callers will never hit this deny.
# Its purpose is to satisfy compliance tooling (e.g., Wiz) that checks for an
# explicit policy-layer enforcement rather than relying on endpoint behaviour.
###############################################################################

data "aws_iam_policy_document" "secure_transport" {
  count = local.attach_policy ? 1 : 0

  statement {
    sid    = "DenyNonSecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.main.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "main" {
  count = local.attach_policy ? 1 : 0

  queue_url = aws_sqs_queue.main.id
  policy    = data.aws_iam_policy_document.secure_transport[0].json
}

