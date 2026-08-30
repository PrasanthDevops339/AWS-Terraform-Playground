################################################################################
# Multiple services on one cluster
#
# Where examples/complete spells out three tiers longhand, this one shows the
# DRY shape: a shared base merged into a per-service override map.
#
# The pattern matters once you pass three or four services. Every service still
# gets its own task definition, IAM wiring, autoscaling policies, alarms and
# deployment configuration - the merge only removes the copy-paste.
#
# Four services, deliberately different from each other:
#
#   web        public, load balanced, blue/green, scales on CPU
#   api        internal, load balanced, rolling, scales on CPU
#   worker     no load balancer, queue consumer, scales on memory
#   scheduler  no load balancer, exactly one task, no autoscaling
################################################################################

locals {
  ##############################################################################
  # Shared base
  #
  # Anything every service agrees on. Per-service maps override by key.
  ##############################################################################

  task_base = {
    execution_role_arn = var.execution_role_arn
    task_role_arn      = var.task_role_arn
    cpu                = 512
    memory             = 1024
  }

  service_base = {
    subnets                 = var.subnet_ids
    enable_execute_command  = true
    enable_ecs_managed_tags = true
    propagate_tags          = "SERVICE"
  }

  # Standard HTTP port mapping, named so Service Connect can be added later
  # without changing the task definition.
  http_port_mappings = [
    {
      name          = "http"
      containerPort = var.container_port
      protocol      = "tcp"
      appProtocol   = "http"
    },
  ]

  ##############################################################################
  # Per-service definitions
  #
  # Only what differs from the base.
  ##############################################################################

  services = {
    web = {
      image           = var.web_image
      security_groups = [var.web_security_group_id]
      port_mappings   = local.http_port_mappings

      service_extra = {
        desired_count                     = 3
        health_check_grace_period_seconds = 60

        # Public tier, so it gets the safer deployment strategy.
        deployment_configuration = {
          strategy             = "BLUE_GREEN"
          bake_time_in_minutes = 10
        }

        target_groups = [
          {
            target_group_arn           = var.web_blue_target_group_arn
            container_name             = "web"
            container_port             = var.container_port
            alternate_target_group_arn = var.web_green_target_group_arn
            production_listener_rule   = var.web_production_listener_rule_arn
          },
        ]
      }

      autoscaling = {
        min_capacity                     = 3
        max_capacity                     = 20
        cpu_scaling_policy_configuration = { target_value = 55 }
      }
    }

    api = {
      image           = var.api_image
      security_groups = [var.api_security_group_id]
      port_mappings   = local.http_port_mappings

      service_extra = {
        desired_count                     = 2
        health_check_grace_period_seconds = 60

        # Internal tier, so a plain rolling update is fine.
        deployment_configuration = {
          strategy                = "ROLLING"
          minimum_healthy_percent = 100
          maximum_percent         = 200
          deployment_circuit_breaker = {
            enable   = true
            rollback = true
          }
        }

        target_groups = [
          {
            target_group_arn = var.api_target_group_arn
            container_name   = "api"
            container_port   = var.container_port
          },
        ]
      }

      autoscaling = {
        min_capacity                     = 2
        max_capacity                     = 12
        cpu_scaling_policy_configuration = { target_value = 60 }
      }
    }

    worker = {
      image           = var.worker_image
      security_groups = [var.worker_security_group_id]
      # No inbound traffic, so no port mappings and no target group.
      port_mappings = null

      service_extra = {
        desired_count = 2

        deployment_configuration = {
          strategy = "ROLLING"
          # A queue consumer can drop to zero healthy briefly without user
          # impact, which makes deployments cheaper.
          minimum_healthy_percent = 0
          maximum_percent         = 200
        }
      }

      # Queue consumers are usually memory-bound rather than CPU-bound.
      autoscaling = {
        min_capacity                        = 2
        max_capacity                        = 30
        create_cpu_scaling_policy           = false
        create_memory_scaling_policy        = true
        memory_scaling_policy_configuration = { target_value = 70 }
      }
    }

    scheduler = {
      image           = var.scheduler_image
      security_groups = [var.worker_security_group_id]
      port_mappings   = null

      service_extra = {
        # Exactly one task: a second would double-fire scheduled jobs.
        desired_count = 1

        deployment_configuration = {
          strategy = "ROLLING"
          # 0/100 guarantees the old task stops before the new one starts, so
          # two schedulers never run at once.
          minimum_healthy_percent = 0
          maximum_percent         = 100
        }
      }

      # Deliberately no autoscaling block - a singleton must stay a singleton.
      autoscaling = null
    }
  }
}

################################################################################
# Assembly
#
# One comprehension turns the maps above into the module's container_config.
################################################################################

module "ecs_multi" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # Target groups are supplied per service, not module-wide.
  load_balanced = true
  target_groups = []

  container_config = {
    for name, svc in local.services : name => merge(
      {
        container_name = name

        task_definition = merge(local.task_base, {
          image               = svc.image
          task_log_group_name = "/ecs/${var.cluster_name}/${name}"
          port_mappings       = svc.port_mappings
        })

        service = merge(local.service_base, {
          security_groups = svc.security_groups
        }, svc.service_extra)

        alarms = {
          enabled        = true
          sns_topic_arns = var.alarm_sns_topic_arns
        }
      },
      # Omit the autoscaling key entirely when null, so the module does not
      # register a scaling target for the singleton scheduler.
      svc.autoscaling == null ? {} : { autoscaling = svc.autoscaling },
    )
  }
}
