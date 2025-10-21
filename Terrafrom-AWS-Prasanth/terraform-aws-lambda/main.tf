# ===============================
# LAMBDA FUNCTION – Lambda resource
# ===============================

locals {
  lambda_arn = coalescelist(
    aws_lambda_function.main.*.arn,
    ["UserDidNotEnabledLambdaCreation"]
  )[0]

  lambda_s3_key = var.upload_to_s3 == true ? aws_s3_object.main.*.key[0] : var.lambda_bucket_key

  account_alias = data.aws_iam_account_alias.current.account_alias
}

# Create lambda function
resource "aws_lambda_function" "main" {
  count = var.create_lambda_function == true ? 1 : 0

  function_name = "${local.account_alias}-${var.lambda_name}"
  description   = var.lambda_description
  role          = var.lambda_role_arn

  # Default handler to "<lambda_name>.lambda_handler" when not explicitly set
  handler = var.lambda_handler == null && var.image_uri == null ? "${var.lambda_name}.lambda_handler" : var.lambda_handler

  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions
  runtime                        = var.runtime
  architectures                  = var.architectures

  ephemeral_storage {
    size = var.ephemeral_storage
  }

  layers       = var.layers
  timeout      = var.timeout
  publish      = var.publish
  kms_key_arn  = var.kms_key_arn
  image_uri    = var.image_uri
  package_type = var.package_type

  # Only set when packaging & uploading via S3 in this module
  source_code_hash  = var.upload_to_s3 == true ? data.archive_file.rendered_zip.*.output_base64sha256[0] : null
  s3_bucket         = var.lambda_bucket_name
  s3_key            = local.lambda_s3_key
  s3_object_version = var.lambda_bucket_object_version

  dynamic "logging_config" {
    for_each = length(var.logging_config) > 0 ? [var.logging_config] : []
    content {
      log_format       = try(logging_config.value.log_format, null)
      log_group        = try(logging_config.value.log_group, null)
      system_log_level = try(logging_config.value.system_log_level, null)
    }
  }

  dynamic "vpc_config" {
    for_each = length(var.vpc_config) > 0 ? [var.vpc_config] : []
    content {
      security_group_ids = try(vpc_config.value.security_group_ids, null)
      subnet_ids         = try(vpc_config.value.subnet_ids, null)
    }
  }

  dynamic "environment" {
    for_each = [true]
    content {
      variables = var.environment
    }
  }

  dynamic "image_config" {
    for_each = length(var.image_config) > 0 ? [var.image_config] : []
    content {
      entry_point       = try(image_config.value.image_config_entry_point, null)
      command           = try(image_config.value.image_config_command, null)
      working_directory = try(image_config.value.image_config_working_directory, null)
    }
  }

  dynamic "dead_letter_config" {
    for_each = length(var.dead_letter_config) > 0 ? [var.dead_letter_config] : []
    content {
      target_arn = try(dead_letter_config.value.dead_letter_target_arn, null)
    }
  }

  dynamic "tracing_config" {
    for_each = length(var.tracing_config) > 0 ? [var.tracing_config] : []
    content {
      mode = try(tracing_config.value.tracing_mode, null)
    }
  }

  dynamic "file_system_config" {
    for_each = length(var.file_system_config) > 0 ? [var.file_system_config] : []
    content {
      local_mount_path = try(file_system_config.value.file_system_local_mount_path, null)
      arn              = try(file_system_config.value.file_system_arn, null)
    }
  }

  tags = merge(var.tags, { Name = "${local.account_alias}-${var.lambda_name}" })
}

resource "aws_lambda_permission" "main" {
  for_each = { for k, v in var.allowed_triggers : k => v if var.create_lambda_function == true && var.create_lambda_permission == true }

  statement_id  = try(each.value.statement_id, null)
  action        = try(each.value.action, "lambda:InvokeFunction")
  function_name = aws_lambda_function.main[0].function_name
  principal     = try(each.value.principal, format("%s.amazonaws.com", try(each.value.service, "")))
  source_arn    = try(each.value.source_arn, null)
}

resource "aws_lambda_event_source_mapping" "main" {
  for_each = { for k, v in var.event_source_mapping : k => v if var.create_lambda_function == true && length(var.event_source_mapping) > 0 }

  function_name                      = aws_lambda_function.main[0].function_name
  event_source_arn                   = try(each.value.event_source_arn, null)
  batch_size                         = try(each.value.batch_size, null)
  maximum_batching_window_in_seconds = try(each.value.maximum_batching_window_in_seconds, null)
  enabled                            = try(each.value.enabled, null)
  starting_position                  = try(each.value.starting_position, null)

  dynamic "filter_criteria" {
    for_each = length(try(flatten([each.value.filter_criteria]), [])) > 0 ? [true] : []
    content {
      dynamic "filter" {
        for_each = try(flatten([each.value.filter_criteria]), [])
        content {
          pattern = try(filter.value.pattern, null)
        }
      }
    }
  }

  dynamic "metrics_config" {
    for_each = try(each.value.metrics_config, null) == null ? [] : [each.value.metrics_config]
    content {
      metrics = metrics_config.value.metrics
    }
  }
}
