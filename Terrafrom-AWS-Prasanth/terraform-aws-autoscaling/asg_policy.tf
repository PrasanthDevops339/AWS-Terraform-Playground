resource "aws_autoscaling_policy" "main" {
  for_each = var.scaling_policies

  name                      = try(each.value.name, each.key)
  region                    = var.region
  autoscaling_group_name    = aws_autoscaling_group.main[0].name
  adjustment_type           = try(each.value.adjustment_type, null)
  policy_type               = try(each.value.policy_type, null)
  estimated_instance_warmup = try(each.value.estimated_instance_warmup, null)
  cooldown                  = try(each.value.cooldown, null)
  min_adjustment_magnitude  = try(each.value.min_adjustment_magnitude, null)
  metric_aggregation_type   = try(each.value.metric_aggregation_type, null)
  scaling_adjustment        = try(each.value.scaling_adjustment, null)

  dynamic "step_adjustment" {
    for_each = try(each.value.step_adjustment, [])
    content {
      scaling_adjustment          = step_adjustment.value.scaling_adjustment
      metric_interval_lower_bound = try(step_adjustment.value.metric_interval_lower_bound, null)
      metric_interval_upper_bound = try(step_adjustment.value.metric_interval_upper_bound, null)
    }
  }

  dynamic "target_tracking_configuration" {
    for_each = try([each.value.target_tracking_configuration], [])
    content {
      target_value    = target_tracking_configuration.value.target_value
      disable_scale_in = try(target_tracking_configuration.value.disable_scale_in, null)

      dynamic "predefined_metric_specification" {
        for_each = try([target_tracking_configuration.value.predefined_metric_specification], [])
        content {
          predefined_metric_type = predefined_metric_specification.value.predefined_metric_type
          resource_label         = try(predefined_metric_specification.value.resource_label, null)
        }
      }

      dynamic "customized_metric_specification" {
        for_each = try([target_tracking_configuration.value.customized_metric_specification], [])
        content {
          dynamic "metric_dimension" {
            for_each = try(customized_metric_specification.value.metric_dimension, [])
            content {
              name  = metric_dimension.value.name
              value = metric_dimension.value.value
            }
          }

          metric_name = try(customized_metric_specification.value.metric_name, null)

          dynamic "metrics" {
            for_each = try(customized_metric_specification.value.metrics, [])
            content {
              expression = try(metrics.value.expression, null)
              id         = metrics.value.id
              label      = try(metrics.value.label, null)

              dynamic "metric_stat" {
                for_each = try([metrics.value.metric_stat], [])
                content {
                  dynamic "metric" {
                    for_each = try([metric_stat.value.metric], [])
                    content {
                      dynamic "dimensions" {
                        for_each = try(metric.value.dimensions, [])
                        content {
                          name  = dimensions.value.name
                          value = dimensions.value.value
                        }
                      }
                      metric_name = metric.value.metric_name
                      namespace   = metric.value.namespace
                    }
                  }
                  stat = metric_stat.value.stat
                  unit = try(metric_stat.value.unit, null)
                }
              }

              return_data = try(metrics.value.return_data, null)
            }
          }

          namespace = try(customized_metric_specification.value.namespace, null)
          statistic = try(customized_metric_specification.value.statistic, null)
          unit      = try(customized_metric_specification.value.unit, null)
        }
      }
    }
  }

  dynamic "predictive_scaling_configuration" {
    for_each = try([each.value.predictive_scaling_configuration], [])
    content {
      max_capacity_breach_behavior = try(predictive_scaling_configuration.value.max_capacity_breach_behavior, null)
      max_capacity_buffer          = try(predictive_scaling_configuration.value.max_capacity_buffer, null)
      mode                         = try(predictive_scaling_configuration.value.mode, null)
      scheduling_buffer_time       = try(predictive_scaling_configuration.value.scheduling_buffer_time, null)

      dynamic "metric_specification" {
        for_each = try([predictive_scaling_configuration.value.metric_specification], [])
        content {
          target_value = metric_specification.value.target_value

          dynamic "predefined_load_metric_specification" {
            for_each = try([metric_specification.value.predefined_load_metric_specification], [])
            content {
              predefined_metric_type = predefined_load_metric_specification.value.predefined_metric_type
              resource_label         = predefined_load_metric_specification.value.resource_label
            }
          }

          dynamic "predefined_metric_pair_specification" {
            for_each = try([metric_specification.value.predefined_metric_pair_specification], [])
            content {
              predefined_metric_type = predefined_metric_pair_specification.value.predefined_metric_type
              resource_label         = predefined_metric_pair_specification.value.resource_label
            }
          }

          dynamic "predefined_scaling_metric_specification" {
            for_each = try([metric_specification.value.predefined_scaling_metric_specification], [])
            content {
              predefined_metric_type = predefined_scaling_metric_specification.value.predefined_metric_type
              resource_label         = predefined_scaling_metric_specification.value.resource_label
            }
          }
        }
      }
    }
  }
}
