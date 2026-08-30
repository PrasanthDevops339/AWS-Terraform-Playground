################################################################################
# Fargate - every deployment type ECS supports
#
# One cluster, six services, each showing a different deployment type on the
# FARGATE launch type:
#
#   rolling      ECS controller / ROLLING      in-place replacement
#   blue_green   ECS controller / BLUE_GREEN   full green fleet, bake, then cut
#   linear       ECS controller / LINEAR       20% of traffic every 3 minutes
#   canary       ECS controller / CANARY       10% canary, bake, then the rest
#   external     EXTERNAL controller           task sets managed outside Terraform
#   spot_worker  FARGATE_SPOT via capacity provider strategy
#
# Traffic shifting is done natively by ECS. There is no CodeDeploy application,
# deployment group, AppSpec or service role anywhere in this stack.
#
# DAEMON scheduling is the one deployment shape absent here: it requires
# container instances, so it lives in the ec2-all-deployment-types example.
#
# The load balancer is an input rather than a resource, so the example stays
# about ECS deployment behaviour instead of rebuilding an ALB.
################################################################################

provider "aws" {
  region = var.region
}

locals {
  # Shared by every service below.
  network = {
    subnets         = var.private_subnet_ids
    security_groups = [var.service_security_group_id]
  }

  port_mappings = [
    {
      name          = "http"
      containerPort = var.container_port
      protocol      = "tcp"
      appProtocol   = "http"
    },
  ]
}

module "ecs" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-ecs"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # Fargate-only cluster, so ec2_capacity_providers is left at its {} default.
  launch_type_default = "FARGATE"
  capacity_providers  = ["FARGATE", "FARGATE_SPOT"]

  # Container Insights is on by default via cluster_settings, which is what
  # makes the RunningTaskCount alarm meaningful.

  container_config = {

    ##########################################################################
    # 1. ROLLING - the default. ECS replaces tasks in place, bounded by the
    #    min-healthy and max percentages. Terraform performs the deployment.
    ##########################################################################
    rolling = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/rolling"
        port_mappings       = local.port_mappings
      }

      service = {
        launch_type   = "FARGATE"
        desired_count = 2

        subnets         = local.network.subnets
        security_groups = local.network.security_groups

        enable_execute_command            = true
        health_check_grace_period_seconds = 60

        deployment_configuration = {
          strategy = "ROLLING"

          # 100/200 holds full capacity throughout and doubles briefly. Drop
          # the minimum to 50 if you would rather not pay for the surge.
          minimum_healthy_percent = 100
          maximum_percent         = 200

          # Aborts and reverts when tasks fail to stabilise.
          deployment_circuit_breaker = {
            enable   = true
            rollback = true
          }
        }

        target_groups = [
          {
            target_group_arn = var.blue_target_group_arn
            container_name   = "app"
            container_port   = var.container_port
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

    ##########################################################################
    # 2. BLUE_GREEN - ECS stands up a full green fleet on the alternate target
    #    group, bakes, shifts 100% of traffic, then tears down blue.
    ##########################################################################
    blue_green = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/blue-green"
        port_mappings       = local.port_mappings
      }

      service = {
        launch_type   = "FARGATE"
        desired_count = 2

        subnets         = local.network.subnets
        security_groups = local.network.security_groups

        deployment_configuration = {
          strategy = "BLUE_GREEN"

          # Soak on the new fleet before blue is terminated. This is the window
          # in which an alarm can still trigger an automatic rollback.
          bake_time_in_minutes = 10

          # ECS assumes this role to reweight the listener rule.
          ecs_alb_service_role_arn = var.ecs_alb_service_role_arn

          alarms = {
            enable      = true
            rollback    = true
            alarm_names = var.rollback_alarm_names
          }
        }

        target_groups = [
          {
            target_group_arn = var.blue_target_group_arn
            container_name   = "app"
            container_port   = var.container_port

            # The three inputs ECS-native traffic shifting needs.
            alternate_target_group_arn = var.green_target_group_arn
            production_listener_rule   = var.production_listener_rule_arn
            # Optional: smoke-test green before the cutover.
            test_listener_rule = var.test_listener_rule_arn
          },
        ]
      }
    }

    ##########################################################################
    # 3. LINEAR - shifts a fixed percentage at a time, pausing between steps.
    #    20% every 3 minutes reaches 100% in roughly 15 minutes.
    ##########################################################################
    linear = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/linear"
        port_mappings       = local.port_mappings
      }

      service = {
        launch_type   = "FARGATE"
        desired_count = 3

        subnets         = local.network.subnets
        security_groups = local.network.security_groups

        deployment_configuration = {
          strategy                 = "LINEAR"
          bake_time_in_minutes     = 5
          ecs_alb_service_role_arn = var.ecs_alb_service_role_arn

          linear_configuration = {
            step_percent              = 20
            step_bake_time_in_minutes = 3
          }

          # Roll back mid-shift if either alarm fires.
          alarms = {
            enable      = true
            rollback    = true
            alarm_names = var.rollback_alarm_names
          }
        }

        target_groups = [
          {
            target_group_arn           = var.blue_target_group_arn
            container_name             = "app"
            container_port             = var.container_port
            alternate_target_group_arn = var.green_target_group_arn
            production_listener_rule   = var.production_listener_rule_arn
          },
        ]
      }
    }

    ##########################################################################
    # 4. CANARY - send a small slice to the new version, hold, then shift the
    #    remainder in one step.
    ##########################################################################
    canary = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/canary"
        port_mappings       = local.port_mappings
      }

      service = {
        launch_type   = "FARGATE"
        desired_count = 4

        subnets         = local.network.subnets
        security_groups = local.network.security_groups

        deployment_configuration = {
          strategy                 = "CANARY"
          bake_time_in_minutes     = 5
          ecs_alb_service_role_arn = var.ecs_alb_service_role_arn

          canary_configuration = {
            canary_percent              = 10
            canary_bake_time_in_minutes = 15
          }

          alarms = {
            enable      = true
            rollback    = true
            alarm_names = var.rollback_alarm_names
          }

          # Lambda hooks gate the canary on your own checks. Omitted entirely
          # when no hook Lambda is supplied.
          lifecycle_hooks = var.canary_hook_lambda_arn == null ? [] : [
            {
              hook_target_arn  = var.canary_hook_lambda_arn
              role_arn         = var.canary_hook_role_arn
              lifecycle_stages = ["POST_TEST_TRAFFIC_SHIFT"]
            },
          ]
        }

        target_groups = [
          {
            target_group_arn           = var.blue_target_group_arn
            container_name             = "app"
            container_port             = var.container_port
            alternate_target_group_arn = var.green_target_group_arn
            production_listener_rule   = var.production_listener_rule_arn
          },
        ]
      }
    }

    ##########################################################################
    # 5. EXTERNAL - ECS creates the service shell only. Task sets, networking
    #    and traffic shifting are driven by a third-party system through the
    #    CreateTaskSet API, so none of those are set on the service.
    ##########################################################################
    external = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/external"
        port_mappings       = local.port_mappings
      }

      service = {
        launch_type   = "FARGATE"
        desired_count = 1

        deployment_controller = {
          type = "EXTERNAL"
        }
      }
    }

    ##########################################################################
    # 6. FARGATE_SPOT through a capacity provider strategy.
    #
    #    Supplying capacity_provider_strategy replaces launch_type - the two
    #    are mutually exclusive in the ECS API, and the module drops
    #    launch_type for you rather than letting the apply fail.
    ##########################################################################
    spot_worker = {
      container_name = "worker"

      task_definition = {
        cpu                 = 256
        memory              = 512
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/spot-worker"
      }

      service = {
        desired_count = 5

        subnets         = local.network.subnets
        security_groups = local.network.security_groups

        capacity_provider_strategy = [
          # Keep one task on on-demand so a Spot interruption cannot empty the
          # service.
          {
            capacity_provider = "FARGATE"
            weight            = 1
            base              = 1
          },
          {
            capacity_provider = "FARGATE_SPOT"
            weight            = 4
          },
        ]
      }
    }
  }

  # A worker has no load balancer, so target groups are supplied per service
  # rather than module-wide.
  load_balanced = true
  target_groups = []
}
