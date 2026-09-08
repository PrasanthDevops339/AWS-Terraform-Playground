data "aws_iam_account_alias" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  partition        = data.aws_partition.current.partition
  region           = data.aws_region.current.region
  account_id       = data.aws_caller_identity.current.account_id
  account_alias    = data.aws_iam_account_alias.current.account_alias
  lambda_name      = "${var.name_prefix}-${local.region}-writer"
  function_name    = "${local.account_alias}-${local.lambda_name}"
  writer_role_arn  = var.create_writer_role ? local.created_writer_role_arn : coalesce(var.writer_role_arn, "invalid")
  writer_role_name = var.create_writer_role ? aws_iam_role.writer[0].name : element(reverse(split("/", coalesce(var.writer_role_arn, "invalid"))), 0)
  lambda_package_bucket = coalesce(
    var.lambda_package_bucket_name,
    "${var.name_prefix}-pkg-${local.account_id}-${local.region}",
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

  # Configuration contract passed to the unchanged shared Lambda module.
  # It is also exposed for callers and offline tests.
  writer_lambda_config = {
    runtime       = "python3.13"
    handler       = "handler.handler"
    memory_size   = 128
    timeout       = 30
    architectures = ["x86_64"]

    # AWS rejects a lowercase "zip". The shared module's package_type default
    # is "zip", so this must be passed explicitly and capitalised.
    package_type = "Zip"

    ephemeral_storage = 512

    # AWS uses -1 for unreserved concurrency; map the wrapper null explicitly.
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
# Lambda deployment-package bucket -- one per member account and region. The shared
# terraform-aws-lambda module deploys only from S3 or a container image; it
# cannot take a local zip. This bucket holds that zip.
# --------------------------------------------------------------------------

resource "aws_s3_bucket" "lambda_package" {
  bucket        = local.lambda_package_bucket
  force_destroy = true
  tags          = var.tags

  lifecycle {
    precondition {
      condition = length(local.account_alias) > 0 && length(local.function_name) <= 64 && alltrue([
        for suffix in ["target-dlq", "lambda-dlq"] : length("${local.account_alias}-${var.name_prefix}-${suffix}") <= 80
      ])
      error_message = "The shared modules require an account alias; alias-prefixed Lambda/SQS names must fit 64/80 characters. Shorten name_prefix or the account alias."
    }
    precondition {
      condition     = length(local.lambda_package_bucket) <= 63
      error_message = "The region-specific package bucket name must fit 63 characters; shorten name_prefix or set lambda_package_bucket_name."
    }
    precondition {
      condition     = startswith(local.writer_role_arn, "arn:${local.partition}:iam::${local.account_id}:role/")
      error_message = "writer_role_arn must belong to this member account and partition."
    }
    precondition {
      condition = alltrue([
        for key in [var.local_kms_key_arn, var.lambda_package_kms_key_arn] :
        key == null ? true : startswith(key, "arn:${local.partition}:kms:${local.region}:${local.account_id}:key/")
      ])
      error_message = "Log and package keys must belong to this member account and region."
    }
  }
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
      sse_algorithm     = var.lambda_package_kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.lambda_package_kms_key_arn
    }
    bucket_key_enabled = var.lambda_package_kms_key_arn != null
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
# Regional runtime permissions for the Lambda execution role
# --------------------------------------------------------------------------

# Every regional deployment adds its own policy to the shared execution role.
resource "aws_iam_role_policy" "writer" {
  name = "${var.name_prefix}-${local.region}-runtime"
  role = local.writer_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs", Effect = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.this.arn}:*"]
      },
      {
        Sid      = "LambdaFailureDestination", Effect = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [module.lambda_dlq.queue_arn]
      }
    ]
  })
}

# --------------------------------------------------------------------------
# Lambda function -- sourced from the shared terraform-aws-lambda module.
# --------------------------------------------------------------------------

module "writer_lambda" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-lambda"

  lambda_name        = local.lambda_name
  lambda_description = "Writes one patch-outcome record per SSM RunPatchBaseline terminal event to the central bucket."
  lambda_role_arn    = local.writer_role_arn
  lambda_handler     = local.writer_lambda_config.handler
  runtime            = local.writer_lambda_config.runtime
  memory_size        = local.writer_lambda_config.memory_size
  timeout            = local.writer_lambda_config.timeout
  architectures      = local.writer_lambda_config.architectures
  package_type       = local.writer_lambda_config.package_type
  ephemeral_storage  = local.writer_lambda_config.ephemeral_storage

  reserved_concurrent_executions = local.writer_lambda_config.reserved_concurrent_executions

  environment = local.writer_lambda_config.environment

  # Region-specific names also make local zip files unique. The shared module
  # derives source_code_hash from the archive so code changes redeploy.
  upload_to_s3       = true
  lambda_script_dir  = "${path.module}/src"
  lambda_bucket_name = aws_s3_bucket.lambda_package.id

  create_lambda_permission = true
  allowed_triggers         = local.allowed_triggers

  tags = var.tags

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.writer,
    aws_iam_role_policy.archive,
    aws_s3_bucket_public_access_block.lambda_package,
    aws_s3_bucket_ownership_controls.lambda_package,
    aws_s3_bucket_server_side_encryption_configuration.lambda_package,
  ]
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

  depends_on = [module.writer_lambda, aws_sqs_queue_policy.target_dlq, aws_lambda_function_event_invoke_config.this]
}

# Canary -- always enabled, proves the plumbing without impersonating a real
# SSM event (PutEvents rejects any source beginning with "aws.").
resource "aws_cloudwatch_event_rule" "canary" {
  count = var.enable_canary ? 1 : 0

  name  = "${var.name_prefix}-canary"
  state = "ENABLED"

  event_pattern = jsonencode({
    source      = ["custom.patch-canary"]
    detail-type = ["canary"]
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

  depends_on = [module.writer_lambda, aws_sqs_queue_policy.target_dlq, aws_lambda_function_event_invoke_config.this]
}

# --------------------------------------------------------------------------
# EventBridge target DLQ and Lambda async failure destination. Both queues
# are sourced unchanged; operators use the central runbook for recovery.
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

resource "aws_sqs_queue_policy" "target_dlq" {
  queue_url = module.target_dlq.queue_url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeSend", Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = module.target_dlq.queue_arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = concat(
          [for rule in aws_cloudwatch_event_rule.ssm : rule.arn],
          var.enable_canary ? [aws_cloudwatch_event_rule.canary[0].arn] : [],
        ) }
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}
