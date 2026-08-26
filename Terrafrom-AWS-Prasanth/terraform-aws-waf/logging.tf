resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.main.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
  depends_on              = [aws_cloudwatch_log_group.main]
  region                  = local.resource_region
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "aws-waf-logs-${local.account_alias}-${var.waf_name}"
  retention_in_days = 90
  region            = local.resource_region
  tags = merge(
    var.tags,
    {
      Name = "aws-waf-logs-${local.account_alias}-${var.waf_name}"
    },
    local.platform_tags,
  )
}

resource "aws_cloudwatch_log_subscription_filter" "main" {
  name            = "waf-logging-filter"
  log_group_name  = aws_cloudwatch_log_group.main.name
  destination_arn = local.destination_arn[local.resource_region]
  distribution    = "Random"
  filter_pattern  = ""
  role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cloudwatch-log-group-role"
  region          = local.resource_region
}

resource "aws_cloudwatch_log_resource_policy" "cw_resource_policy" {
  count           = var.create_individual_cloudwatch_policy ? 1 : 0
  policy_document = data.aws_iam_policy_document.cw_policy_doc.json
  policy_name     = "${local.account_alias}-${var.waf_name}-cw-policy"
  region          = local.resource_region
}

data "aws_iam_policy_document" "cw_policy_doc" {
  statement {
    sid    = "AllowWAFStream"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = ["${aws_cloudwatch_log_group.main.arn}:*"]
    condition {
      test     = "ArnLike"
      values   = ["arn:aws:logs:${local.resource_region}:${data.aws_caller_identity.current.account_id}:*"]
      variable = "aws:SourceArn"
    }
    condition {
      test     = "StringEquals"
      values   = [tostring(data.aws_caller_identity.current.account_id)]
      variable = "aws:SourceAccount"
    }
  }
}
