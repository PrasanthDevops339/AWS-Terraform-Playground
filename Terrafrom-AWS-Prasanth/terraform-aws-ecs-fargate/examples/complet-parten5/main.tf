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

module "pattern5_app" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    }
  ]

  cluster_configuration = local.cluster_configuration

  # Pattern 5 keeps only the edge tier behind a load balancer. Internal calls
  # use Service Connect inside the shared namespace.
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
          },
          {
            name  = "API_BASE_URL"
            value = "http://api:8080"
          }
        ]

        # The edge tier exposes one public listener through the external ALB.
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

        # Client-only Service Connect. The frontend calls the internal API by
        # the "api" discovery name but does not publish its own internal
        # endpoint through Service Connect.
        service_connect = {
          enabled   = true
          namespace = var.service_connect_namespace_arn
          services  = []
        }
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

        # The API is private. It publishes a Service Connect endpoint, but it
        # has no target group and no direct external ingress.
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
        desired_count           = 2
        enable_execute_command  = true
        enable_ecs_managed_tags = true
        security_groups         = [var.api_security_group_id]
        subnets                 = var.subnet_ids

        service_connect = {
          enabled   = true
          namespace = var.service_connect_namespace_arn

          services = [
            {
              port_name      = "api-http"
              discovery_name = "api"
              client_aliases = [
                {
                  dns_name = "api"
                  port     = 8080
                }
              ]
            }
          ]
        }
      }

      autoscaling = {
        min_capacity = 2
        max_capacity = 8

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
          },
          {
            name  = "API_BASE_URL"
            value = "http://api:8080"
          }
        ]

        # Pattern 5 workers stay private and do not expose inbound HTTP or RPC
        # ports. They can still act as Service Connect clients.
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

        # Client-only Service Connect keeps outbound name resolution consistent
        # without publishing a worker endpoint.
        service_connect = {
          enabled   = true
          namespace = var.service_connect_namespace_arn
          services  = []
        }
      }

      autoscaling = {
        min_capacity = 1
        max_capacity = 6

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
            max_capacity = 6
          }
        ]
      }
    }
  }
}
