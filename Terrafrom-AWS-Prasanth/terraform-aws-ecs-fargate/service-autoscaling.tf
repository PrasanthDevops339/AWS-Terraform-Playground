#########################################
# ECS Service Auto Scaling (per service)
#########################################

locals {
  # Pull per-service autoscaling config from container_config
  autoscaling_policy = { for service, config in var.container_config : service => try(config.autoscaling, {}) }
  account_alias      = data.aws_iam_account_alias.current.account_alias
}

# Register each ECS service as an Application Auto Scaling target
resource "aws_appautoscaling_target" "main" {
  for_each           = local.autoscaling_policy

  max_capacity       = try(each.value.max_capacity, 3)
  min_capacity       = try(each.value.min_capacity, 1)

  # service/<cluster-name>/<service-name>
  resource_id        = "service/${aws_ecs_cluster.main[0].name}/${aws_ecs_service.main[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}" })
}

#########################################
# TargetTracking: CPU
#########################################
resource "aws_appautoscaling_policy" "cpu_scaling" {
  for_each = {
    for k, v in local.autoscaling_policy :
    k => v if try(v.create_cpu_scaling_policy, true)
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
    scale_in_cooldown  = try(each.value.cpu_scaling_policy_configuration.scale_in_cooldown, 300)
    scale_out_cooldown = try(each.value.cpu_scaling_policy_configuration.scale_out_cooldown, 300)
    target_value       = try(each.value.cpu_scaling_policy_configuration.target_value, 60)
  }
}

#########################################
# TargetTracking: Memory
#########################################
resource "aws_appautoscaling_policy" "memory_scaling" {
  for_each = {
    for k, v in local.autoscaling_policy :
    k => v if try(v.create_memory_scaling_policy, true)
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
    scale_in_cooldown  = try(each.value.memory_scaling_policy_configuration.scale_in_cooldown, 300)
    scale_out_cooldown = try(each.value.memory_scaling_policy_configuration.scale_out_cooldown, 300)
    target_value       = try(each.value.memory_scaling_policy_configuration.target_value, 80)
  }
}

#########################################
# Step Scaling (optional)
#########################################
resource "aws_appautoscaling_policy" "step_policy" {
  for_each = {
    for k, v in local.autoscaling_policy :
    k => v if try(v.create_step_scaling_policy, false)
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
