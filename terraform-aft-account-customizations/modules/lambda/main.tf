
#------------------------------
# LAMBDA FUNCTION - Lambda resource
#------------------------------

# Locals
locals {
  lambda_arn = coalescelist(
    aws_lambda_function.lambda_function[*].arn,
    ["UserDidNotEnabledLambdaCreation"]
  )[0]

  sns_topic_arn = var.lambda_trigger_sns_topic_arn == null ?
    element(concat(aws_sns_topic.sns_topic[*].arn, [""]), 0) :
    var.lambda_trigger_sns_topic_arn

  lambda_s3_key = coalescelist(
    aws_s3_object.lambda_package_object[*].key,
    ["UserDidNotEnabledS3BucketUpload"]
  )[0]

  random_uuid = coalescelist(
    random_uuid.key[*].result,
    ["lambda"]
  )[0]

  assume_role_policy = var.assume_role_policy == "" ? data.aws_iam_policy_document.assume_role_policy.json : var.assume_role_policy

  # If workspace variable is default value then set string blank otherwise set string to hyphen current workspace value
  # this allows for dynamic resource names
  workspace_string = var.workspace == "none" ? "" : "-${var.workspace}"
}

# Create lambda function
resource "aws_lambda_function" "lambda_function" {
  count = var.create_lambda_function ? 1 : 0

  function_name = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-function${local.workspace_string}"
  description   = var.lambda_description

  role = var.lambda_role_arn == null ? aws_iam_role.lambda[0].arn : var.lambda_role_arn

  handler = (var.lambda_handler == null && var.image_uri == null) ? "${var.lambda_name}.lambda_handler" : var.lambda_handler
  runtime = var.runtime

  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions
  timeout                        = var.timeout
  layers                         = var.layers
  publish                        = var.publish

  kms_key_arn  = var.kms_key_arn
  image_uri    = var.image_uri
  package_type = var.package_type

  ephemeral_storage {
    size = var.ephemeral_storage
  }

  # ZIP path if not uploading to S3 and not using image
  filename = (!var.upload_to_s3 && var.image_uri == null) ? data.archive_file.rendered_zip[0].output_path : null

  # Hash only for ZIP
  source_code_hash = (var.image_uri == null) ? data.archive_file.rendered_zip[0].output_base64sha256 : null

  # S3 package path when enabled
  s3_bucket         = var.upload_to_s3 ? var.lambda_bucket_name : null
  s3_key            = var.upload_to_s3 ? local.lambda_s3_key : null
  s3_object_version = var.upload_to_s3 ? var.lambda_bucket_object_version : null

  lifecycle {
    precondition {
      condition = (
        (!var.use_custom_log_group && (var.log_group_name == "" || var.log_group_name == null)) ||
        (var.use_custom_log_group && trim(coalesce(var.log_group_name, ""), " ") != "")
      )
      error_message = "To use custom logs, \"use_custom_log_group\" must be true and you must provide a name for the target log group"
    }
  }

  dynamic "logging_config" {
    for_each = (var.use_custom_log_group && var.log_group_name != null) ? [true] : []
    content {
      log_format       = var.log_format
      log_group        = var.log_group_name
      system_log_level = var.system_log_level
    }
  }

  dynamic "vpc_config" {
    for_each = (var.vpc_subnet_ids != null && var.vpc_security_group_ids != null) ? [true] : []
    content {
      security_group_ids = var.vpc_security_group_ids
      subnet_ids         = var.vpc_subnet_ids
    }
  }

  dynamic "environment" {
    for_each = length(keys(var.environment_variables)) == 0 ? [] : [true]
    content {
      variables = var.environment_variables
    }
  }

  dynamic "image_config" {
    for_each = (
      length(var.image_config_entry_point) > 0 ||
      length(var.image_config_command) > 0 ||
      var.image_config_working_directory != null
    ) ? [true] : []
    content {
      entry_point       = var.image_config_entry_point
      command           = var.image_config_command
      working_directory = var.image_config_working_directory
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn == null ? [] : [true]
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  dynamic "tracing_config" {
    for_each = var.tracing_mode == null ? [] : [true]
    content {
      mode = var.tracing_mode
    }
  }

  dynamic "file_system_config" {
    for_each = (var.file_system_arn != null && var.file_system_local_mount_path != null) ? [true] : []
    content {
      local_mount_path = var.file_system_local_mount_path
      arn              = var.file_system_arn
    }
  }

  tags = merge(
    {
      "Name" = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-function${local.workspace_string}"
    },
    var.tags
  )
}

# Optionally create lambda permission for calling function from API / other services
resource "aws_lambda_permission" "this" {
  count = var.create_lambda_function && var.create_lambda_permission ? 1 : 0

  statement_id  = var.statement_id
  action        = var.action
  function_name = aws_lambda_function.lambda_function[0].function_name
  principal     = var.principal
  source_arn    = var.source_arn
}
