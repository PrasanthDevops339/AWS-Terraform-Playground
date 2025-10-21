# RDS Instance Log group
resource "aws_cloudwatch_log_group" "subscription" {
  count             = length(var.enabled_cloudwatch_logs_exports) > 0 ? length(var.enabled_cloudwatch_logs_exports) : 0
  name              = "/aws/rds/instance/${local.account_alias}-${var.identifier}/${var.enabled_cloudwatch_logs_exports[count.index]}"
  retention_in_days = var.logs_retention_period
}

# RDS Event Subscription (optional)
resource "aws_db_event_subscription" "subscription" {
  count            = var.enable_db_event_subscription ? 1 : 0
  name             = "${local.account_alias}-${var.identifier}-db-event-subscription"
  sns_topic        = var.sns_topic_arn
  source_type      = "db-instance"
  source_ids       = [aws_db_instance.main.identifier]
  event_categories = var.db_events_list
  tags             = merge(var.tags, { Name = "${local.account_alias}-${var.identifier}-db-event-subscription" })
}
