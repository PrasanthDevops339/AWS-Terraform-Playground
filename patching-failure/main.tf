locals {
  partition     = data.aws_partition.current.partition
  region        = data.aws_region.current.region
  account_id    = data.aws_caller_identity.current.account_id
  account_alias = data.aws_iam_account_alias.current.account_alias

  # The shared Lambda module prefixes the account alias to lambda_name.
  lambda_name   = "${var.name_prefix}-${local.region}-writer"
  function_name = "${local.account_alias}-${local.lambda_name}"

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
  # It is also exposed as an output for offline tests.
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

    # Write to the existing app_log/ group; Lambda creates the log streams
    # (named after the function) itself. system_log_level is JSON-only.
    logging_config = {
      log_format = "Text"
      log_group  = data.aws_cloudwatch_log_group.app.name
    }

    # AWS uses -1 for unreserved concurrency; map the null input explicitly.
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
  # shared module creates these from allowed_triggers.
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
# Lambda deployment-package bucket. The shared terraform-aws-lambda module
# deploys only from S3 or a container image; this bucket holds the zip.
# --------------------------------------------------------------------------

resource "aws_s3_bucket" "lambda_package" {
  bucket        = local.lambda_package_bucket
  force_destroy = true
  tags          = var.tags

  lifecycle {
    precondition {
      condition     = length(local.account_alias) > 0 && length(local.function_name) <= 64
      error_message = "The shared Lambda module requires an account alias, and the alias-prefixed function name must fit 64 characters. Shorten name_prefix or the account alias."
    }
    precondition {
      condition     = length(local.lambda_package_bucket) <= 63
      error_message = "The package bucket name must fit 63 characters; shorten name_prefix or set lambda_package_bucket_name."
    }
    precondition {
      condition     = startswith(var.lambda_package_kms_key_arn, "arn:${local.partition}:kms:${local.region}:${local.account_id}:key/")
      error_message = "lambda_package_kms_key_arn must be a key in this account and region."
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.lambda_package_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# --------------------------------------------------------------------------
# Lambda function -- sourced from the shared terraform-aws-lambda module.
# --------------------------------------------------------------------------

module "writer_lambda" {
  source = "../Terrafrom-AWS-Prasanth/terraform-aws-lambda"

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

  environment    = local.writer_lambda_config.environment
  logging_config = local.writer_lambda_config.logging_config

  # The shared module zips src/ and derives source_code_hash so code changes redeploy.
  upload_to_s3       = true
  lambda_script_dir  = "${path.module}/src"
  lambda_bucket_name = aws_s3_bucket.lambda_package.id

  create_lambda_permission = true
  allowed_triggers         = local.allowed_triggers

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.runtime,
    aws_iam_role_policy.archive,
    aws_s3_bucket_public_access_block.lambda_package,
    aws_s3_bucket_ownership_controls.lambda_package,
    aws_s3_bucket_server_side_encryption_configuration.lambda_package,
  ]
}

# Async retries for function errors (e.g. S3 PutObject denied). Without the DLQ
# enhancement, events that exhaust these retries are visible only in the Lambda
# logs and the AsyncEventsDropped metric.
resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = module.writer_lambda.lambda_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600

  # ENHANCEMENT (DLQ): uncomment to send failed async invocations to SQS.
  # destination_config {
  #   on_failure {
  #     destination = module.lambda_dlq.queue_arn
  #   }
  # }
}

# --------------------------------------------------------------------------
# EventBridge rules -- three SSM rules plus an optional canary, all on the
# default bus (AWS service events are delivered there only). Quick Setup patch
# policies run AWS-RunPatchBaseline, which these patterns match by prefix.
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

  # ENHANCEMENT (DLQ): uncomment to capture EventBridge delivery failures.
  # dead_letter_config {
  #   arn = module.target_dlq.queue_arn
  # }

  depends_on = [
    module.writer_lambda,
    aws_lambda_function_event_invoke_config.this,
    # aws_sqs_queue_policy.target_dlq, # ENHANCEMENT (DLQ)
  ]
}

# Canary -- proves the plumbing without impersonating a real SSM event
# (PutEvents rejects any source beginning with "aws.").
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

  # ENHANCEMENT (DLQ): uncomment to capture EventBridge delivery failures.
  # dead_letter_config {
  #   arn = module.target_dlq.queue_arn
  # }

  depends_on = [
    module.writer_lambda,
    aws_lambda_function_event_invoke_config.this,
    # aws_sqs_queue_policy.target_dlq, # ENHANCEMENT (DLQ)
  ]
}

# ---------------------------------------------------------------------------
# ENHANCEMENT (disabled for POC): SQS dead-letter queues.
#
# To restore, uncomment:
#   1. the two modules and the queue policy below,
#   2. dead_letter_config + depends_on lines in both event targets,
#   3. destination_config in aws_lambda_function_event_invoke_config.this,
#   4. the LambdaFailureDestination statement in iam.tf,
#   5. the target_dlq_url / lambda_dlq_url outputs in outputs.tf.
# The shared SQS module prefixes the account alias; names must fit 80 chars.
# ---------------------------------------------------------------------------

# module "target_dlq" {
#   source = "../Terrafrom-AWS-Prasanth/terraform-aws-sqs"
#
#   queue_name                = "${var.name_prefix}-target-dlq"
#   message_retention_seconds = 1209600
#
#   # Standalone queue, not a redrive target of a "main" queue.
#   enable_dlq = false
#
#   # The shared module's only built-in policy is a deny-non-TLS statement; the
#   # EventBridge allow-policy this queue needs is attached separately below.
#   enable_secure_transport = false
#
#   tags = var.tags
# }
#
# module "lambda_dlq" {
#   source = "../Terrafrom-AWS-Prasanth/terraform-aws-sqs"
#
#   queue_name                = "${var.name_prefix}-lambda-dlq"
#   message_retention_seconds = 1209600
#   enable_dlq                = false
#   enable_secure_transport   = false
#
#   tags = var.tags
# }
#
# resource "aws_sqs_queue_policy" "target_dlq" {
#   queue_url = module.target_dlq.queue_url
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Sid       = "AllowEventBridgeSend", Effect = "Allow"
#       Principal = { Service = "events.amazonaws.com" }
#       Action    = "sqs:SendMessage"
#       Resource  = module.target_dlq.queue_arn
#       Condition = {
#         ArnEquals = { "aws:SourceArn" = concat(
#           [for rule in aws_cloudwatch_event_rule.ssm : rule.arn],
#           var.enable_canary ? [aws_cloudwatch_event_rule.canary[0].arn] : [],
#         ) }
#         StringEquals = { "aws:SourceAccount" = local.account_id }
#       }
#     }]
#   })
# }
