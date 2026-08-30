locals {
  cluster_configuration = [
    merge(
      {
        execute_command_configuration = {
          logging = "OVERRIDE"
          log_configuration = {
            cloud_watch_log_group_name = var.exec_log_group_name
          }
        }
      },
      var.fargate_ephemeral_storage_kms_key_id != null || var.managed_storage_kms_key_id != null ? {
        managed_storage_configuration = {
          fargate_ephemeral_storage_kms_key_id = var.fargate_ephemeral_storage_kms_key_id
          kms_key_id                           = var.managed_storage_kms_key_id
        }
      } : {}
    )
  ]
}

module "three_tier_app" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # Prefer on-demand Fargate, but allow service-level overrides to shift some
  # workloads such as workers to FARGATE_SPOT.
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    }
  ]

  cluster_configuration = local.cluster_configuration

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace_arn
  }

  deployment_strategy_default = "ROLLING"

  deployment_configuration = {
    deployment_circuit_breaker = {
      enable   = true
      rollback = true
    }
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  container_config = {
    frontend = {
      container_name = "frontend"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.frontend_image
        execution_role_arn  = var.frontend_execution_role_arn
        task_role_arn       = var.frontend_task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/frontend"

        environment = [
          {
            name  = "APP_ENV"
            value = "frontend"
          }
        ]

        port_mappings = [
          {
            name          = "http"
            containerPort = 80
            hostPort      = 80
            protocol      = "tcp"
            appProtocol   = "http"
          }
        ]
      }

      service = {
        desired_count                     = 2
        enable_execute_command            = true
        enable_ecs_managed_tags           = true
        health_check_grace_period_seconds = 60
        security_groups                   = [var.frontend_security_group_id]
        subnets                           = var.subnet_ids

        target_groups = [
          {
            target_group_arn = var.frontend_target_group_arn
            container_name   = "frontend"
            container_port   = 80
          }
        ]
      }

      autoscaling = {
        min_capacity = 2
        max_capacity = 6

        cpu_scaling_policy_configuration = {
          target_value       = 60
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }

        memory_scaling_policy_configuration = {
          target_value       = 75
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }
      }
    }

    api = {
      container_name = "api"

      task_definition = {
        cpu                 = 1024
        memory              = 2048
        image               = var.api_image
        execution_role_arn  = var.api_execution_role_arn
        task_role_arn       = var.api_task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/api"

        environment = [
          {
            name  = "APP_ENV"
            value = "api"
          }
        ]

        # Service Connect requires a named port mapping.
        port_mappings = [
          {
            name          = "api-http"
            containerPort = 8080
            hostPort      = 8080
            protocol      = "tcp"
            appProtocol   = "http"
          }
        ]
      }

      service = {
        desired_count                     = 2
        enable_execute_command            = true
        enable_ecs_managed_tags           = true
        health_check_grace_period_seconds = 60
        security_groups                   = [var.api_security_group_id]
        subnets                           = var.subnet_ids

        deployment_configuration = {
          strategy             = "CANARY"
          bake_time_in_minutes = 10

          canary_configuration = {
            canary_percent              = 10
            canary_bake_time_in_minutes = 10
          }

          # No ecs_alb_service_role_arn on purpose. The module creates the ECS
          # infrastructure role that reweights the listener rule, because the
          # provider requires advanced_configuration.role_arn. Set the variable
          # only to reuse a role you already manage.
          ecs_alb_service_role_arn = var.api_ecs_alb_service_role_arn

          alarms = {
            enable      = length(var.api_deployment_alarm_names) > 0
            rollback    = true
            alarm_names = var.api_deployment_alarm_names
          }
        }

        target_groups = [
          {
            target_group_arn           = var.api_blue_target_group_arn
            alternate_target_group_arn = var.api_green_target_group_arn
            production_listener_rule   = var.api_production_listener_rule_arn
            container_name             = "api"
            container_port             = 8080
          }
        ]

        service_connect = {
          enabled   = true
          namespace = var.service_connect_namespace_arn

          services = [
            {
              port_name      = "api-http"
              discovery_name = "api"
              client_aliases = [
                {
                  port     = 8080
                  dns_name = "api"
                }
              ]
            }
          ]
        }
      }

      autoscaling = {
        min_capacity = 2
        max_capacity = 10

        cpu_scaling_policy_configuration = {
          target_value       = 60
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }

        memory_scaling_policy_configuration = {
          target_value       = 75
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }

        create_alb_request_count_policy = true
        alb_request_count_policy_configuration = {
          alb_arn_suffix          = var.alb_arn_suffix
          target_group_arn_suffix = var.api_blue_target_group_arn_suffix
          target_value            = 500
          scale_in_cooldown       = 300
          scale_out_cooldown      = 60
        }
      }
    }

    worker = {
      container_name = "worker"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.worker_image
        execution_role_arn  = var.worker_execution_role_arn
        task_role_arn       = var.worker_task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/worker"

        environment = [
          {
            name  = "APP_ENV"
            value = "worker"
          }
        ]

        # No inbound port mapping. This tier is a Service Connect client only.
        port_mappings = []
      }

      service = {
        desired_count           = 2
        enable_execute_command  = true
        enable_ecs_managed_tags = true
        security_groups         = [var.worker_security_group_id]
        subnets                 = var.subnet_ids

        capacity_provider_strategy = [
          {
            capacity_provider = "FARGATE_SPOT"
            weight            = 4
            base              = 1
          },
          {
            capacity_provider = "FARGATE"
            weight            = 1
            base              = 0
          }
        ]

        service_connect = {
          enabled   = true
          namespace = var.service_connect_namespace_arn
          services  = []
        }
      }

      autoscaling = {
        min_capacity = 1
        max_capacity = 8

        cpu_scaling_policy_configuration = {
          target_value       = 70
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }

        scheduled_actions = [
          {
            name         = "scale-down-nights"
            schedule     = "cron(0 22 * * ? *)"
            timezone     = "UTC"
            min_capacity = 1
            max_capacity = 2
          },
          {
            name         = "scale-up-mornings"
            schedule     = "cron(0 7 * * ? *)"
            timezone     = "UTC"
            min_capacity = 2
            max_capacity = 8
          }
        ]
      }
    }
  }
}
