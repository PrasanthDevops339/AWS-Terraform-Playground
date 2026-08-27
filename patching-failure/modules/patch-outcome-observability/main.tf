locals {
  # Derive region/account/partition from a resource ARN this module owns
  # rather than the deprecated data.aws_region.current.name (removed in
  # provider 6.x; .region does not exist on the data source in 5.x).
  log_group_arn_parts = split(":", aws_cloudwatch_log_group.this.arn)
  partition           = local.log_group_arn_parts[1]
  region              = local.log_group_arn_parts[3]
  account_id          = local.log_group_arn_parts[4]

  function_name = "${var.name_prefix}-writer"

  rule_definitions = {
    invocation_success = {
      detail_type = "EC2 Command Invocation Status-change Notification"
      statuses    = ["Success"]
    }
    invocation_failure = {
      detail_type = "EC2 Command Invocation Status-change Notification"
      statuses    = var.invocation_failure_statuses
    }
    command_failure = {
      detail_type = "EC2 Command Status-change Notification"
      statuses    = var.command_failure_statuses
    }
  }
}

# --------------------------------------------------------------------------
# Lambda package
# --------------------------------------------------------------------------

data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

# --------------------------------------------------------------------------
# Lambda log group -- created before the function so Terraform owns it
# instead of Lambda auto-creating it with no explicit retention.
# --------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.lambda_log_retention_in_days
  kms_key_id        = var.local_kms_key_arn
  tags              = var.tags
}

# --------------------------------------------------------------------------
# IAM execution role -- name is load-bearing, see variables.tf
# --------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "writer" {
  name                 = var.writer_role_name
  path                 = var.iam_role_path
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  tags                 = var.tags
}

data "aws_iam_policy_document" "writer" {
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid       = "S3WriteOnly"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:${local.partition}:s3:::${var.archive_bucket_name}/${var.archive_s3_prefix}/*"]
  }

  dynamic "statement" {
    for_each = var.archive_kms_key_arn != null ? [1] : []
    content {
      sid       = "KmsEncryptOnly"
      effect    = "Allow"
      actions   = ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"]
      resources = [var.archive_kms_key_arn]
    }
  }

  statement {
    sid       = "TargetDlq"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_dlq.arn]
  }

  statement {
    sid       = "SsmReadOnly"
    effect    = "Allow"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommands", "ssm:DescribeInstanceInformation"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.include_instance_tags ? [1] : []
    content {
      sid       = "Ec2DescribeForTags"
      effect    = "Allow"
      actions   = ["ec2:DescribeInstances"]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "writer" {
  name   = "${var.writer_role_name}-inline"
  role   = aws_iam_role.writer.id
  policy = data.aws_iam_policy_document.writer.json
}

# --------------------------------------------------------------------------
# Lambda function
# --------------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.writer.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  memory_size   = 128
  timeout       = 30

  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      BUCKET_NAME           = var.archive_bucket_name
      S3_PREFIX             = var.archive_s3_prefix
      KMS_KEY_ARN           = var.archive_kms_key_arn
      OBJECT_ACL            = var.archive_object_acl == null ? "" : var.archive_object_acl
      ENRICH                = tostring(var.enable_enrichment)
      INCLUDE_INSTANCE_TAGS = tostring(var.include_instance_tags)
      LOG_LEVEL             = var.log_level
    }
  }

  depends_on = [aws_cloudwatch_log_group.this]

  tags = var.tags
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600

  destination_config {
    on_failure {
      destination = aws_sqs_queue.lambda_dlq.arn
    }
  }
}

# --------------------------------------------------------------------------
# EventBridge rules -- three SSM rules plus an optional canary, all on the
# default bus (AWS service events are delivered there only).
# --------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rule_definitions

  name  = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  state = var.rules_enabled ? "ENABLED" : "DISABLED"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = [each.value.detail_type]
    detail = {
      status        = each.value.statuses
      document-name = [{ prefix = var.patch_document_name_prefix }]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.rule_definitions

  rule = aws_cloudwatch_event_rule.this[each.key].name
  arn  = aws_lambda_function.this.arn

  dead_letter_config {
    arn = aws_sqs_queue.target_dlq.arn
  }
}

resource "aws_lambda_permission" "this" {
  for_each = local.rule_definitions

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.key].arn
}

# Canary -- always enabled, proves the plumbing without impersonating a real
# SSM event (PutEvents rejects any source beginning with "aws.").
resource "aws_cloudwatch_event_rule" "canary" {
  count = var.enable_canary ? 1 : 0

  name  = "${var.name_prefix}-canary"
  state = "ENABLED"

  event_pattern = jsonencode({
    source = ["custom.patch-canary"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "canary" {
  count = var.enable_canary ? 1 : 0

  rule = aws_cloudwatch_event_rule.canary[0].name
  arn  = aws_lambda_function.this.arn

  dead_letter_config {
    arn = aws_sqs_queue.target_dlq.arn
  }
}

resource "aws_lambda_permission" "canary" {
  count = var.enable_canary ? 1 : 0

  statement_id  = "AllowEventBridge-canary"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.canary[0].arn
}

# --------------------------------------------------------------------------
# Two DLQs -- different failure points, both required. See BUILD-INSTRUCTIONS
# section 6: with no metrics tier these plus the canary are the entire safety
# net.
# --------------------------------------------------------------------------

resource "aws_sqs_queue" "target_dlq" {
  name                      = "${var.name_prefix}-target-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${var.name_prefix}-lambda-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

data "aws_iam_policy_document" "target_dlq" {
  statement {
    sid       = "AllowEventBridgeSend"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.target_dlq.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:events:*:${local.account_id}:rule/${var.name_prefix}-*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "target_dlq" {
  queue_url = aws_sqs_queue.target_dlq.id
  policy    = data.aws_iam_policy_document.target_dlq.json
}
