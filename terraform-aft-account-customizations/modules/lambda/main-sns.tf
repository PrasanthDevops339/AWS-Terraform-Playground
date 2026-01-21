
#------------------------------
# LAMBDA FUNCTION - SNS Resources - event trigger
#------------------------------

# Creates SNS Topic used to trigger lambda functions
resource "aws_sns_topic" "sns_topic" {
  count = var.create_lambda_function && var.create_sns_event_trigger && var.lambda_trigger_sns_topic_arn == null ? 1 : 0

  name   = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-topic${local.workspace_string}"
  policy = var.lambda_trigger_sns_topic_policy

  tags = merge(
    {
      "Name" = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-topic${local.workspace_string}"
    },
    var.tags
  )
}

# Creates SNS topic subscription with the lambda function
resource "aws_sns_topic_subscription" "sns-topic" {
  count = var.create_lambda_function && var.create_sns_event_trigger ? 1 : 0

  topic_arn = local.sns_topic_arn
  protocol  = "lambda"
  endpoint  = local.lambda_arn
}

# Creates permission that allow SNS topic to invoke the lambda function
resource "aws_lambda_permission" "sns_invoke" {
  count = var.create_lambda_function && var.create_sns_event_trigger ? 1 : 0

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = local.lambda_arn
  principal     = "sns.amazonaws.com"
  source_arn    = local.sns_topic_arn
}
