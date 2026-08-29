data "aws_iam_account_alias" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  # Provider floor is now >= 6.0.0 (raised by the shared terraform-aws-sqs
  # module), where data.aws_region exposes .region -- so the ARN-splitting
  # workaround the 5.x/6.x straddle needed is no longer required.
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  # The shared terraform-aws-lambda module prefixes every function name with the
  # account alias, so the real function -- and therefore its auto-created log
  # group -- is "<alias>-<name_prefix>-writer". This module owns that log group
  # explicitly (for retention), so the name must match exactly.
  function_name = "${data.aws_iam_account_alias.current.account_alias}-${var.name_prefix}-writer"

  lambda_package_bucket = coalesce(
    var.lambda_package_bucket_name,
    "${var.name_prefix}-pkg-${local.account_id}",
  )

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

  # One Lambda permission per EventBridge rule (SSM rules + the canary). The
  # shared module creates these from allowed_triggers -- EventBridge -> Lambda
  # is a resource policy, not an IAM role.
  allowed_triggers = merge(
    {
      for key, rule in aws_cloudwatch_event_rule.ssm : key => {
        statement_id = "AllowEventBridge-${key}"
        principal    = "events.amazonaws.com"
        source_arn   = rule.arn
      }
    },
    var.enable_canary ? {
      canary = {
        statement_id = "AllowEventBridge-canary"
        principal    = "events.amazonaws.com"
        source_arn   = aws_cloudwatch_event_rule.canary[0].arn
      }
    } : {},
  )
}

# --------------------------------------------------------------------------
# Lambda deployment-package bucket -- one per member account. The shared
# terraform-aws-lambda module deploys only from S3 or a container image; it
# cannot take a local zip. This bucket holds that zip.
# --------------------------------------------------------------------------

resource "aws_s3_bucket" "lambda_package" {
  bucket        = local.lambda_package_bucket
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "lambda_package" {
  bucket = aws_s3_bucket.lambda_package.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "lambda_package" {
  bucket = aws_s3_bucket.lambda_package.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_package" {
  bucket = aws_s3_bucket.lambda_package.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.local_kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.local_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# --------------------------------------------------------------------------
# Lambda log group -- created before the function so Terraform owns it with an
# explicit retention instead of Lambda auto-creating it.
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
    sid       = "LambdaDlq"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [module.lambda_dlq.queue_arn]
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
# Lambda function -- sourced from the shared terraform-aws-lambda module.
# --------------------------------------------------------------------------

module "writer_lambda" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-lambda"

  lambda_name        = "${var.name_prefix}-writer"
  lambda_description = "Writes one patch-outcome record per SSM RunPatchBaseline terminal event to the central bucket."
  lambda_role_arn    = aws_iam_role.writer.arn
  lambda_handler     = "handler.handler"
  runtime            = "python3.13"
  memory_size        = 128
  timeout            = 30
  architectures      = ["x86_64"]
  ephemeral_storage  = 512

  reserved_concurrent_executions = var.reserved_concurrency == null ? -1 : var.reserved_concurrency

  environment = {
    BUCKET_NAME           = var.archive_bucket_name
    S3_PREFIX             = var.archive_s3_prefix
    KMS_KEY_ARN           = var.archive_kms_key_arn == null ? "" : var.archive_kms_key_arn
    OBJECT_ACL            = var.archive_object_acl == null ? "" : var.archive_object_acl
    ENRICH                = tostring(var.enable_enrichment)
    INCLUDE_INSTANCE_TAGS = tostring(var.include_instance_tags)
    LOG_LEVEL             = var.log_level
  }

  # Package: zip src/ and upload to the per-account bucket. source_code_hash
  # is set from the archive hash inside the module, so code changes redeploy.
  upload_to_s3       = true
  lambda_script_dir  = "${path.module}/src"
  lambda_bucket_name = aws_s3_bucket.lambda_package.id

  create_lambda_permission = true
  allowed_triggers         = local.allowed_triggers

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = module.writer_lambda.lambda_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600

  destination_config {
    on_failure {
      destination = module.lambda_dlq.queue_arn
    }
  }
}

# --------------------------------------------------------------------------
# EventBridge rules -- three SSM rules plus an optional canary, all on the
# default bus (AWS service events are delivered there only).
# --------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "ssm" {
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

resource "aws_cloudwatch_event_target" "ssm" {
  for_each = local.rule_definitions

  rule = aws_cloudwatch_event_rule.ssm[each.key].name
  arn  = module.writer_lambda.lambda_arn

  dead_letter_config {
    arn = module.target_dlq.queue_arn
  }
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
  arn  = module.writer_lambda.lambda_arn

  dead_letter_config {
    arn = module.target_dlq.queue_arn
  }
}

# --------------------------------------------------------------------------
# Two DLQs -- different failure points, both required. See BUILD-INSTRUCTIONS
# section 6: with no metrics tier these plus the canary are the entire safety
# net. Sourced from the shared terraform-aws-sqs module.
# --------------------------------------------------------------------------

module "target_dlq" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-sqs"

  queue_name                = "${var.name_prefix}-target-dlq"
  message_retention_seconds = 1209600

  # Standalone queue, not a redrive target of a "main" queue.
  enable_dlq = false

  # The shared module's only built-in policy is a deny-non-TLS statement; the
  # EventBridge allow-policy this queue needs is attached separately below.
  enable_secure_transport = false

  tags = var.tags
}

module "lambda_dlq" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-sqs"

  queue_name                = "${var.name_prefix}-lambda-dlq"
  message_retention_seconds = 1209600
  enable_dlq                = false
  enable_secure_transport   = false

  tags = var.tags
}

data "aws_iam_policy_document" "target_dlq" {
  statement {
    sid       = "AllowEventBridgeSend"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [module.target_dlq.queue_arn]

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
  queue_url = module.target_dlq.queue_url
  policy    = data.aws_iam_policy_document.target_dlq.json
}
