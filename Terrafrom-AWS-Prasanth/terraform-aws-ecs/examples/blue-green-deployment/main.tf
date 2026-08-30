################################################################################
# Blue/green deployment
#
# One service using the ECS-native BLUE_GREEN strategy. ECS performs the
# deployment itself: no CodeDeploy application, deployment group, AppSpec or
# service role is involved.
#
# What ECS does on each deployment:
#
#   1. Stands up a green task set and registers it in the alternate target
#      group.
#   2. Waits for the green targets to pass health checks.
#   3. Optionally routes test traffic to green via test_listener_rule.
#   4. Reweights the production listener rule from blue to green.
#   5. Bakes for bake_time_in_minutes, during which an alarm can still roll the
#      deployment back.
#   6. Tears down blue.
#
# LINEAR and CANARY are the same wiring with a different strategy block - see
# the bottom of this file.
################################################################################

module "ecs_blue_green" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  container_config = {
    app = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = var.log_group_name

        port_mappings = [
          {
            name          = "http"
            containerPort = var.container_port
            protocol      = "tcp"
            appProtocol   = "http"
          },
        ]
      }

      service = {
        desired_count                     = 2
        subnets                           = var.subnet_ids
        security_groups                   = [var.service_security_group_id]
        enable_execute_command            = true
        health_check_grace_period_seconds = 60

        deployment_configuration = {
          strategy = "BLUE_GREEN"

          # Soak time on green after traffic has shifted, before blue is torn
          # down. This is the window in which an alarm can still trigger an
          # automatic rollback, so it is worth more than the default.
          bake_time_in_minutes = 10

          # Roll back automatically if a named alarm fires mid-deployment.
          # The alarms must already exist when the deployment runs; to use this
          # module's own alarms, apply once with the list empty and then feed
          # back the alarm_names_for_rollback output.
          alarms = {
            enable      = length(var.rollback_alarm_names) > 0
            rollback    = true
            alarm_names = var.rollback_alarm_names
          }

          # ecs_alb_service_role_arn is deliberately not set. The module creates
          # the ECS infrastructure role that reweights the listener rule,
          # because advanced_configuration.role_arn is required by the provider.
        }

        target_groups = [
          {
            # Blue: the group currently serving production.
            target_group_arn = var.blue_target_group_arn
            container_name   = "app"
            container_port   = var.container_port

            # Green: ECS registers the new task set here, then shifts to it.
            alternate_target_group_arn = var.green_target_group_arn

            # The listener RULE whose weights ECS rewrites. This is a rule ARN
            # (".../listener-rule/app/<lb>/<id>/<listener>/<rule>"), not a
            # listener ARN. Passing a listener ARN fails at apply, not at plan.
            production_listener_rule = var.production_listener_rule_arn

            # Optional. Routes test traffic to green before the production cut,
            # so you can smoke-test the new version.
            test_listener_rule = var.test_listener_rule_arn
          },
        ]
      }

      autoscaling = {
        min_capacity = 2
        max_capacity = 10

        cpu_scaling_policy_configuration = {
          target_value = 60
        }
      }

      alarms = {
        enabled        = true
        sns_topic_arns = var.alarm_sns_topic_arns
      }
    }
  }
}

################################################################################
# The other two traffic-shifting strategies
#
# Same target_groups wiring, same infrastructure role, only the
# deployment_configuration block differs:
#
#   # Shift 20% of traffic every 3 minutes, reaching 100% in ~15 minutes.
#   deployment_configuration = {
#     strategy             = "LINEAR"
#     bake_time_in_minutes = 5
#     linear_configuration = {
#       step_percent              = 20
#       step_bake_time_in_minutes = 3
#     }
#   }
#
#   # Send 10% to the new version, hold 15 minutes, then shift the rest.
#   deployment_configuration = {
#     strategy             = "CANARY"
#     bake_time_in_minutes = 5
#     canary_configuration = {
#       canary_percent              = 10
#       canary_bake_time_in_minutes = 15
#     }
#   }
################################################################################
