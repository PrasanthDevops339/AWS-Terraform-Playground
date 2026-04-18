########################################
# examples/complete/main.tf
#
# Fully-blown 3-tier reference example:
#   frontend — public nginx, ROLLING, public ALB, autoscaling
#   api      — Node.js API, CANARY, internal ALB, EFS, Service Connect, autoscaling
#   worker   — background processor, ROLLING, no LB, scheduled autoscaling
########################################

module "three_tier_app" {
  source = "../../"

  vpc_id       = data.aws_vpc.main.id
  cluster_name = "${var.environment}-three-tier"

  # ── Capacity providers: prefer FARGATE, allow SPOT for workers ──────────────
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    }
  ]

  # ── Service Connect namespace (api <-> worker tier-to-tier) ─────────────────
  enable_service_connect = true

  service_connect_configuration = {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.app.arn
  }

  # ── ECS Exec — encrypted via KMS, logs to CloudWatch ────────────────────────
  cluster_configuration = [{
    execute_command_configuration = {
      kms_key_id = module.kms.key_id
      logging    = "OVERRIDE"
      log_configuration = {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = "/ecs/${var.environment}/exec-logs"
      }
    }
  }]

  # ── EFS volume for api tier ──────────────────────────────────────────────────
  efs_volumes = [{
    name = "api-shared-storage"
    efs_volume_configuration = [{
      file_system_id     = module.efs.id
      root_directory     = "/api"
      transit_encryption = "ENABLED"
      authorization_config = {
        iam = "ENABLED"
      }
    }]
  }]

  # ── Default deployment strategy (frontend + worker use this) ────────────────
  deployment_strategy_default = "ROLLING"

  deployment_configuration = {
    deployment_circuit_breaker = {
      enable   = true
      rollback = true
    }
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  tags = var.tags

  ########################################
  # container_config — one entry per tier
  ########################################
  container_config = {

    ##############################################################
    # TIER 1: frontend
    # ROLLING strategy | public ALB | autoscaling CPU + memory
    ##############################################################
    "frontend" = {
      task_definition = {
        cpu    = 512
        memory = 1024

        execution_role_arn = module.iam_frontend.execution_role_arn
        task_role_arn      = module.iam_frontend.task_role_arn

        image           = "${module.ecr_frontend.repository_url}:${var.image_tag}"
        container_port  = 80
        host_port       = 80
        task_log_group_name = "/ecs/${var.environment}/frontend"

        environment = [
          { name = "ENV",      value = var.environment },
          { name = "API_URL",  value = "http://api.${var.environment}.local:8080" }
        ]

        secrets = [
          { name = "SESSION_SECRET", valueFrom = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/frontend/session_secret" }
        ]
      }

      service = {
        desired_count          = 2
        enable_execute_command = true
        force_new_deployment   = false
        security_groups        = [module.sg_frontend.security_group_id]
        subnets                = data.aws_subnets.private.ids

        # Per-service target groups (public ALB → frontend)
        target_groups = [
          {
            target_group_arn = module.alb_public.target_groups["frontend-blue"].arn
            container_name   = "frontend"
            container_port   = 80
          }
        ]
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
      }

      alarms = {
        enabled          = true
        sns_topic_arns   = [module.alerts.sns_topic_arn]
        cpu_threshold    = 85
        memory_threshold = 90
        min_task_count   = 2
      }
    }

    ##############################################################
    # TIER 2: api
    # CANARY strategy | internal ALB | EFS | Service Connect
    ##############################################################
    "api" = {
      task_definition = {
        cpu    = 1024
        memory = 2048

        execution_role_arn = module.iam_api.execution_role_arn
        task_role_arn      = module.iam_api.task_role_arn

        image           = "${module.ecr_api.repository_url}:${var.image_tag}"
        container_port  = 8080
        host_port       = 8080
        task_log_group_name = "/ecs/${var.environment}/api"

        environment = [
          { name = "ENV",      value = var.environment },
          { name = "PORT",     value = "8080" }
        ]

        secrets = [
          { name = "DB_PASSWORD",  valueFrom = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/api/db_password" },
          { name = "JWT_SECRET",   valueFrom = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/api/jwt_secret" }
        ]

        # EFS mount for shared upload storage
        mountPoints = [{
          sourceVolume  = "api-shared-storage"
          containerPath = "/app/uploads"
          readOnly      = false
        }]

        ephemeral_storage = {
          size_in_gib = 30
        }
      }

      service = {
        desired_count          = 2
        enable_execute_command = true
        force_new_deployment   = false
        security_groups        = [module.sg_api.security_group_id]
        subnets                = data.aws_subnets.private.ids

        # CANARY deployment strategy overrides module default
        deployment_configuration = {
          strategy             = "CANARY"
          bake_time_in_minutes = 10

          canary_configuration = {
            canary_percent              = 10
            canary_bake_time_in_minutes = 10
          }

          # ECS-native B/G requires alternate TG + ECS ALB service role
          ecs_alb_service_role_arn = module.iam_api.ecs_alb_service_role_arn

          alarms = {
            enable      = true
            rollback    = true
            alarm_names = [
              "${var.environment}-api-cpu-high",
              "${var.environment}-api-memory-high"
            ]
          }
        }

        # Blue + green target groups for CANARY traffic shifting
        target_groups = [
          {
            target_group_arn           = module.alb_internal.target_groups["api-blue"].arn
            alternate_target_group_arn = module.alb_internal.target_groups["api-green"].arn
            production_listener_rule   = module.alb_internal.listeners["api-http"].arn
            container_name             = "api"
            container_port             = 8080
          }
        ]

        # Service Connect — exposes api:8080 to other services via Cloud Map
        service_connect = {
          enabled   = true
          namespace = aws_service_discovery_http_namespace.app.arn

          services = [{
            port_name      = "api-http"
            discovery_name = "api"
            client_aliases = [{
              port     = 8080
              dns_name = "api"
            }]
          }]
        }
      }

      autoscaling = {
        min_capacity = 2
        max_capacity = 20

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

        # Scale on ALB request count (traffic-driven)
        create_alb_request_count_policy = true
        alb_request_count_policy_configuration = {
          alb_arn_suffix          = module.alb_internal.load_balancer_arn_suffix
          target_group_arn_suffix = module.alb_internal.target_groups["api-blue"].arn_suffix
          target_value            = 500
          scale_in_cooldown       = 300
          scale_out_cooldown      = 60
        }
      }

      alarms = {
        enabled          = true
        sns_topic_arns   = [module.alerts.sns_topic_arn]
        cpu_threshold    = 80
        memory_threshold = 85
        min_task_count   = 2
      }
    }

    ##############################################################
    # TIER 3: worker
    # ROLLING strategy | no LB | FARGATE_SPOT | scheduled scaling
    ##############################################################
    "worker" = {
      task_definition = {
        cpu    = 512
        memory = 1024

        execution_role_arn = module.iam_worker.execution_role_arn
        task_role_arn      = module.iam_worker.task_role_arn

        image           = "${module.ecr_worker.repository_url}:${var.image_tag}"
        container_port  = 0  # no inbound port — worker polls SQS
        task_log_group_name = "/ecs/${var.environment}/worker"

        environment = [
          { name = "ENV",       value = var.environment },
          { name = "QUEUE_URL", value = "https://sqs.${var.region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.environment}-jobs" }
        ]
      }

      service = {
        desired_count          = 2
        enable_execute_command = true
        force_new_deployment   = false
        security_groups        = [module.sg_worker.security_group_id]
        subnets                = data.aws_subnets.private.ids

        # Use FARGATE_SPOT to reduce worker cost
        capacity_provider_strategy = [
          { capacity_provider = "FARGATE_SPOT", weight = 4, base = 1 },
          { capacity_provider = "FARGATE",      weight = 1, base = 0 }
        ]
      }

      autoscaling = {
        min_capacity = 1
        max_capacity = 15

        cpu_scaling_policy_configuration = {
          target_value       = 70
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }

        # Scale workers down at night, back up in the morning (UTC)
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
            max_capacity = 15
          }
        ]
      }

      alarms = {
        enabled          = true
        sns_topic_arns   = [module.alerts.sns_topic_arn]
        cpu_threshold    = 85
        memory_threshold = 90
        min_task_count   = 1
      }
    }
  }
}

########################################
# Cloud Map namespace for Service Connect
########################################

resource "aws_service_discovery_http_namespace" "app" {
  name        = "${var.environment}.local"
  description = "Service Connect namespace for ${var.environment} environment"
  tags        = var.tags
}
