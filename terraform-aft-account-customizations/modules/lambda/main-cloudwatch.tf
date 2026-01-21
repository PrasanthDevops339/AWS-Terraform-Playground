
#------------------------------
# LAMBDA FUNCTION - Cloudwatch Resources - event trigger
#------------------------------

# Creates Cloudwatch log group to store lambda execution logs
resource "aws_cloudwatch_log_group" "lambda_cloudwatch_log_group" {
  count = var.create_lambda_function && !var.use_custom_log_group ? 1 : 0

  name              = "/aws/lambda/${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-function${local.workspace_string}"
  retention_in_days = var.lambda_logs_retention_period
  kms_key_id        = var.kms_key_arn

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }

  tags = merge(
    {
      "Name" = "/aws/lambda/${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-function${local.workspace_string}"
    },
    var.tags
  )
}

# Creates Cloudwatch event rule to trigger lambda function
resource "aws_cloudwatch_event_rule" "lambda_cloudwatch_event_rule" {
  count = var.create_lambda_function && var.create_cloudwatch_event_trigger ? 1 : 0

  name                = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-event-rule${local.workspace_string}"
  description         = var.cloudwatch_event_description
  schedule_expression = var.schedule_expression
  event_pattern       = var.event_pattern
  role_arn            = var.cloudwatch_role_arn
  state               = var.enable_cloudwatch_event

  tags = merge(
    {
      "Name" = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-lambda-event-rule${local.workspace_string}"
    },
    var.tags
  )
}

# Creates Cloudwatch event target assigned to lambda function
resource "aws_cloudwatch_event_target" "lambda_cloudwatch_event_target" {
  count = var.create_lambda_function && var.create_cloudwatch_event_trigger ? 1 : 0

  target_id = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-lambda-target"
  rule      = aws_cloudwatch_event_rule.lambda_cloudwatch_event_rule[0].name
  arn       = local.lambda_arn
}

# Creates permission to allow Cloudwatch events to execute it on schedule
resource "aws_lambda_permission" "cloudwatch" {
  count = var.create_lambda_function && var.create_cloudwatch_event_trigger ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = local.lambda_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_cloudwatch_event_rule[0].arn
}
