#########################################
# ECS Service Auto Scaling (per service)
#
# Reads scaling config from:
#   container_config[key].autoscaling
#
# Supported policies:
#   - CPU target tracking     (create_cpu_scaling_policy, default true)
#   - Memory target tracking  (create_memory_scaling_policy, default true)
#   - ALB request count       (create_alb_request_count_policy, default false)
#   - Step scaling            (create_step_scaling_policy, default false)
#   - Scheduled actions       (scheduled_actions list)
#########################################

locals {
  account_alias = data.aws_iam_account_alias.current.account_alias

  # Only ECS-controller services are registered as autoscaling targets
  # (CodeDeploy services are managed separately)
  autoscaling_services = {
    for k, v in var.container_config : k => try(v.autoscaling, null)
    if try(v.service.deployment_controller.type, "ECS") == "ECS" && try(v.autoscaling, null) != null
  }

  # Flatten scheduled actions: "svc-action_name" => { svc, action }
  scheduled_actions = merge([
    for svc_name, autoscaling in local.autoscaling_services : {
      for action in try(autoscaling.scheduled_actions, []) :
      "${svc_name}-${action.name}" => merge(action, { svc_name = svc_name })
    }
  ]...)
}

#########################################
# Application Auto Scaling Target
#########################################

resource "aws_appautoscaling_target" "main" {
  for_each = local.autoscaling_services

  max_capacity       = try(each.value.max_capacity, 3)
  min_capacity       = try(each.value.min_capacity, 1)
  resource_id        = "service/${aws_ecs_cluster.main[0].name}/${aws_ecs_service.main[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}" })
}

#########################################
# Target Tracking: CPU Utilization
#########################################

resource "aws_appautoscaling_policy" "cpu_scaling" {
  for_each = {
    for k, v in local.autoscaling_services : k => v
    if try(v.create_cpu_scaling_policy, true)
  }

  name               = "${local.account_alias}-${each.key}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.main[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.main[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.main[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = try(each.value.cpu_scaling_policy_configuration.target_value, 60)
    scale_in_cooldown  = try(each.value.cpu_scaling_policy_configuration.scale_in_cooldown, 300)
    scale_out_cooldown = try(each.value.cpu_scaling_policy_configuration.scale_out_cooldown, 60)
    disable_scale_in   = try(each.value.cpu_scaling_policy_configuration.disable_scale_in, false)
  }
}

#########################################
# Target Tracking: Memory Utilization
#########################################

resource "aws_appautoscaling_policy" "memory_scaling" {
  for_each = {
    for k, v in local.autoscaling_services : k => v
    if try(v.create_memory_scaling_policy, true)
  }

  name               = "${local.account_alias}-${each.key}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.main[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.main[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.main[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = try(each.value.memory_scaling_policy_configuration.target_value, 80)
    scale_in_cooldown  = try(each.value.memory_scaling_policy_configuration.scale_in_cooldown, 300)
    scale_out_cooldown = try(each.value.memory_scaling_policy_configuration.scale_out_cooldown, 60)
    disable_scale_in   = try(each.value.memory_scaling_policy_configuration.disable_scale_in, false)
  }
}

#########################################
# Target Tracking: ALB Request Count Per Target
# Enable via: create_alb_request_count_policy = true
# Requires:   alb_request_count_policy_configuration.alb_arn_suffix
#             alb_request_count_policy_configuration.target_group_arn_suffix
#########################################

resource "aws_appautoscaling_policy" "alb_request_count" {
  for_each = {
    for k, v in local.autoscaling_services : k => v
    if try(v.create_alb_request_count_policy, false)
  }

  name               = "${local.account_alias}-${each.key}-alb-request-count"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.main[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.main[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.main[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${each.value.alb_request_count_policy_configuration.alb_arn_suffix}/${each.value.alb_request_count_policy_configuration.target_group_arn_suffix}"
    }
    target_value       = try(each.value.alb_request_count_policy_configuration.target_value, 1000)
    scale_in_cooldown  = try(each.value.alb_request_count_policy_configuration.scale_in_cooldown, 300)
    scale_out_cooldown = try(each.value.alb_request_count_policy_configuration.scale_out_cooldown, 60)
    disable_scale_in   = try(each.value.alb_request_count_policy_configuration.disable_scale_in, false)
  }
}

#########################################
# Step Scaling (optional, for custom metric alarms)
# Enable via: create_step_scaling_policy = true
#########################################

resource "aws_appautoscaling_policy" "step_policy" {
  for_each = {
    for k, v in local.autoscaling_services : k => v
    if try(v.create_step_scaling_policy, false)
  }

  name               = "${local.account_alias}-${each.key}-step-scaling"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.main[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.main[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.main[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type          = try(each.value.step_scaling_policy_configuration.adjustment_type, "ChangeInCapacity")
    cooldown                 = try(each.value.step_scaling_policy_configuration.cooldown, 300)
    metric_aggregation_type  = try(each.value.step_scaling_policy_configuration.metric_aggregation_type, "Average")
    min_adjustment_magnitude = try(each.value.step_scaling_policy_configuration.min_adjustment_magnitude, null)

    step_adjustment {
      metric_interval_upper_bound = try(each.value.step_scaling_policy_configuration.metric_interval_upper_bound, null)
      metric_interval_lower_bound = try(each.value.step_scaling_policy_configuration.metric_interval_lower_bound, null)
      scaling_adjustment          = try(each.value.step_scaling_policy_configuration.scaling_adjustment, null)
    }
  }
}

#########################################
# Scheduled Scaling Actions
# Add to autoscaling block:
#   scheduled_actions = [
#     { name = "scale-down-nights", schedule = "cron(0 22 * * ? *)", min_capacity = 1, max_capacity = 2 }
#     { name = "scale-up-mornings", schedule = "cron(0 7 * * ? *)",  min_capacity = 2, max_capacity = 10 }
#   ]
#########################################

resource "aws_appautoscaling_scheduled_action" "main" {
  for_each = local.scheduled_actions

  name               = each.key
  service_namespace  = aws_appautoscaling_target.main[each.value.svc_name].service_namespace
  scalable_dimension = aws_appautoscaling_target.main[each.value.svc_name].scalable_dimension
  resource_id        = aws_appautoscaling_target.main[each.value.svc_name].resource_id
  schedule           = each.value.schedule
  timezone           = try(each.value.timezone, "UTC")
  start_time         = try(each.value.start_time, null)
  end_time           = try(each.value.end_time, null)

  scalable_target_action {
    min_capacity = try(each.value.min_capacity, null)
    max_capacity = try(each.value.max_capacity, null)
  }
}
