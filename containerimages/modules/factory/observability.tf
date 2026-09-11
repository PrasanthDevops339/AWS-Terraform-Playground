resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = aws_kms_key.primary.arn
}
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Principal = { AWS = "${local.account_arn}:root" }, Action = "sns:*", Resource = aws_sns_topic.alerts.arn },
    { Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.alerts.arn,
    Condition = { StringEquals = { "aws:SourceAccount" = var.account_id }, ArnLike = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.primary_region}:${var.account_id}:alarm:${var.name}-*" } } }
  ] })
}
resource "aws_cloudwatch_event_rule" "monitor" {
  name                = "${var.name}-monitor"
  schedule_expression = "rate(15 minutes)"
}
resource "aws_cloudwatch_event_rule" "findings" {
  name = "${var.name}-findings"
  event_pattern = jsonencode({ source = ["aws.inspector2"], "detail-type" = ["Inspector2 Finding"], account = [var.account_id],
  detail = { severity = ["CRITICAL"], resources = { type = ["AWS_ECR_CONTAINER_IMAGE"], details = { awsEcrContainerImage = { repositoryName = [local.approved_name] } } } } })
}
resource "aws_cloudwatch_event_target" "monitor" {
  for_each  = { timer = aws_cloudwatch_event_rule.monitor.name, finding = aws_cloudwatch_event_rule.findings.name }
  rule      = each.value
  target_id = "monitor"
  arn       = aws_lambda_function.workers["monitor"].arn
  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}
resource "aws_lambda_permission" "monitor" {
  for_each       = { timer = aws_cloudwatch_event_rule.monitor.arn, finding = aws_cloudwatch_event_rule.findings.arn }
  statement_id   = "EventBridge${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.workers["monitor"].function_name
  principal      = "events.amazonaws.com"
  source_arn     = each.value
  source_account = var.account_id
}
# Cross-region forwarding preserves the original Region in Inspector events.
resource "aws_cloudwatch_event_rule" "replica_scans" {
  provider      = aws.replica
  name          = "${var.name}-replica-scans"
  event_pattern = jsonencode({ source = ["aws.inspector2"], "detail-type" = ["Inspector2 Scan", "Inspector2 Finding"], account = [var.account_id] })
}
resource "aws_iam_role" "forward" {
  name = "${var.name}-replica-events"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole",
    Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.replica_scans.arn }, StringEquals = { "aws:SourceAccount" = var.account_id } }
  }] })
}
resource "aws_iam_role_policy" "forward" {
  role   = aws_iam_role.forward.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "events:PutEvents", Resource = "arn:aws:events:${var.primary_region}:${var.account_id}:event-bus/default" }] })
}
resource "aws_cloudwatch_event_target" "replica_scans" {
  provider  = aws.replica
  rule      = aws_cloudwatch_event_rule.replica_scans.name
  target_id = "primary-bus"
  arn       = "arn:aws:events:${var.primary_region}:${var.account_id}:event-bus/default"
  role_arn  = aws_iam_role.forward.arn
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 20
  }
  depends_on = [aws_iam_role_policy.forward]
}
locals {
  alarm_specs = {
    blocked             = { namespace = "ContainerImages", metric = "ReleaseBlocked", dimensions = { Factory = var.name }, missing = "notBreaching" }
    withdrawn           = { namespace = "ContainerImages", metric = "ReleaseWithdrawn", dimensions = { Factory = var.name }, missing = "notBreaching" }
    scan_timeout        = { namespace = "ContainerImages", metric = "ScanTimeout", dimensions = { Factory = var.name }, missing = "notBreaching" }
    replication_timeout = { namespace = "ContainerImages", metric = "ReplicationTimeout", dimensions = { Factory = var.name }, missing = "notBreaching" }
    heartbeat           = { namespace = "ContainerImages", metric = "BuildHeartbeatMissing", dimensions = { Factory = var.name }, missing = "breaching" }
    workflow_failed     = { namespace = "AWS/States", metric = "ExecutionsFailed", dimensions = { StateMachineArn = local.state_arn }, missing = "notBreaching" }
    workflow_timeout    = { namespace = "AWS/States", metric = "ExecutionsTimedOut", dimensions = { StateMachineArn = local.state_arn }, missing = "notBreaching" }
    dead_letters        = { namespace = "AWS/SQS", metric = "ApproximateNumberOfMessagesVisible", dimensions = { QueueName = aws_sqs_queue.dlq.name }, missing = "notBreaching" }
    ingest_errors       = { namespace = "AWS/Lambda", metric = "Errors", dimensions = { FunctionName = aws_lambda_function.workers["ingest"].function_name }, missing = "notBreaching" }
    monitor_errors      = { namespace = "AWS/Lambda", metric = "Errors", dimensions = { FunctionName = aws_lambda_function.workers["monitor"].function_name }, missing = "notBreaching" }
  }
}
resource "aws_cloudwatch_metric_alarm" "factory" {
  for_each            = local.alarm_specs
  alarm_name          = "${var.name}-${each.key}"
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 2
  datapoints_to_alarm = 1
  period              = each.key == "heartbeat" ? 1800 : 300
  statistic           = "Maximum"
  treat_missing_data  = each.value.missing
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_dashboard" "factory" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = [{ type = "metric", x = 0, y = 0, width = 24, height = 8, properties = {
    title   = "AL2023 release outcomes", region = var.primary_region, period = 300, stat = "Sum",
    metrics = [for metric in ["ReleaseSucceeded", "ReleaseBlocked", "ReleaseWithdrawn", "ScanTimeout", "ReplicationTimeout"] : ["ContainerImages", metric, "Factory", var.name]]
  } }] })
}
