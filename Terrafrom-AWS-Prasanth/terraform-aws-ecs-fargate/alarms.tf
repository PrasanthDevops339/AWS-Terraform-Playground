########################################
# Per-service CloudWatch Alarms
#
# Driven by container_config[key].alarms:
#   enabled           = true
#   sns_topic_arns    = ["arn:aws:sns:..."]
#   cpu_threshold     = 80   (default)
#   memory_threshold  = 85   (default)
#   min_task_count    = 1    (default; triggers when running tasks < this)
#
# All alarms are optional and only created when alarms.enabled = true.
########################################

locals {
  alarm_services = {
    for k, v in var.container_config : k => v
    if try(v.alarms.enabled, false) == true
  }
}

########################################
# CPU Utilization High
########################################

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.alarm_services

  alarm_name          = "${local.account_alias}-${each.key}-cpu-high"
  alarm_description   = "ECS service ${each.key} CPU utilization exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = try(each.value.alarms.cpu_evaluation_periods, 2)
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = try(each.value.alarms.cpu_period, 60)
  statistic           = "Average"
  threshold           = try(each.value.alarms.cpu_threshold, 80)
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main[0].name
    ServiceName = aws_ecs_service.main[each.key].name
  }

  alarm_actions = try(each.value.alarms.sns_topic_arns, [])
  ok_actions    = try(each.value.alarms.sns_topic_arns, [])

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-cpu-high" })
}

########################################
# Memory Utilization High
########################################

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = local.alarm_services

  alarm_name          = "${local.account_alias}-${each.key}-memory-high"
  alarm_description   = "ECS service ${each.key} memory utilization exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = try(each.value.alarms.memory_evaluation_periods, 2)
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = try(each.value.alarms.memory_period, 60)
  statistic           = "Average"
  threshold           = try(each.value.alarms.memory_threshold, 85)
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main[0].name
    ServiceName = aws_ecs_service.main[each.key].name
  }

  alarm_actions = try(each.value.alarms.sns_topic_arns, [])
  ok_actions    = try(each.value.alarms.sns_topic_arns, [])

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-memory-high" })
}

########################################
# Running Task Count Low
########################################

resource "aws_cloudwatch_metric_alarm" "task_count_low" {
  for_each = local.alarm_services

  alarm_name          = "${local.account_alias}-${each.key}-task-count-low"
  alarm_description   = "ECS service ${each.key} running task count fell below minimum"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = try(each.value.alarms.task_count_evaluation_periods, 1)
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = try(each.value.alarms.task_count_period, 60)
  statistic           = "Average"
  threshold           = try(each.value.alarms.min_task_count, 1)
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main[0].name
    ServiceName = aws_ecs_service.main[each.key].name
  }

  alarm_actions = try(each.value.alarms.sns_topic_arns, [])
  ok_actions    = try(each.value.alarms.sns_topic_arns, [])

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-task-count-low" })
}
