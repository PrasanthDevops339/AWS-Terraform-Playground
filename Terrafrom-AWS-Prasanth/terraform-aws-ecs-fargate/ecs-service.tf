########################################
# ecs-service.tf
########################################

resource "aws_ecs_service" "main" {
  for_each = {
    for k, v in var.container_config : k => v
    if try(v.service.deployment_controller.type, "ECS") == "ECS"
  }

  name                   = "${local.account_alias}-${each.key}"
  cluster                = aws_ecs_cluster.main[0].id
  task_definition        = aws_ecs_task_definition.main[each.key].arn
  desired_count          = try(each.value.service.desired_count, 1)
  propagate_tags         = try(each.value.service.propagate_tags, "SERVICE")
  # Suppress launch_type when capacity_provider_strategy is set
  launch_type            = length(try(each.value.service.capacity_provider_strategy, [])) > 0 ? null : "FARGATE"
  platform_version       = try(each.value.service.platform_version, "LATEST")
  scheduling_strategy    = "REPLICA"
  enable_execute_command = try(each.value.service.enable_execute_command, false)
  force_new_deployment   = try(each.value.service.force_new_deployment, false)
  wait_for_steady_state  = try(each.value.service.wait_for_steady_state, false)

  tags = merge(var.tags, {
    "Name" = "${local.account_alias}-${each.key}"
  })

  # Deployment controller (ECS, CODE_DEPLOY, EXTERNAL)
  deployment_controller {
    type = try(each.value.service.deployment_controller.type, "ECS")
  }

  # ============================================================================
  # Rolling deployment thresholds — top-level in AWS provider 6.x
  # ============================================================================
  deployment_maximum_percent         = try(each.value.service.deployment_configuration.maximum_percent, var.deployment_configuration.maximum_percent)
  deployment_minimum_healthy_percent = try(each.value.service.deployment_configuration.minimum_healthy_percent, var.deployment_configuration.minimum_healthy_percent)

  # Circuit breaker — top-level block in AWS provider 6.x
  dynamic "deployment_circuit_breaker" {
    for_each = try(each.value.service.deployment_configuration.deployment_circuit_breaker, null) != null ? [each.value.service.deployment_configuration.deployment_circuit_breaker] : var.deployment_configuration.deployment_circuit_breaker != null ? [var.deployment_configuration.deployment_circuit_breaker] : []
    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  # ============================================================================
  # ECS-native deployment strategy (AWS provider >= 6.4.0)
  #
  # Supported strategies per-service via:
  #   container_config[key].service.deployment_configuration.strategy
  #
  #   ROLLING    — classic rolling update (default)
  #   BLUE_GREEN — full env alongside, instant traffic shift, bake time
  #   LINEAR     — gradual % shift (step_percent every step_bake_time_in_minutes)
  #   CANARY     — small canary %, bake, full cutover
  # ============================================================================
  deployment_configuration {
    # Per-service strategy overrides module default
    strategy = try(
      each.value.service.deployment_configuration.strategy,
      var.deployment_strategy_default
    )

    # Bake time only valid for non-ROLLING strategies
    bake_time_in_minutes = try(each.value.service.deployment_configuration.strategy, var.deployment_strategy_default) != "ROLLING" ? try(each.value.service.deployment_configuration.bake_time_in_minutes, 5) : null

    # CloudWatch alarm-based rollback (all strategies)
    dynamic "alarms" {
      for_each = try(each.value.service.deployment_configuration.alarms, null) != null ? [each.value.service.deployment_configuration.alarms] : var.deployment_configuration.alarms != null ? [var.deployment_configuration.alarms] : []
      content {
        enable      = alarms.value.enable
        rollback    = alarms.value.rollback
        alarm_names = alarms.value.alarm_names
      }
    }

    # LINEAR: gradual traffic shift — e.g. 25% every 5 min
    dynamic "linear_configuration" {
      for_each = try(each.value.service.deployment_configuration.strategy, var.deployment_strategy_default) == "LINEAR" ? [try(each.value.service.deployment_configuration.linear_configuration, {})] : []
      content {
        step_percent              = try(linear_configuration.value.step_percent, 25)
        step_bake_time_in_minutes = try(linear_configuration.value.step_bake_time_in_minutes, 5)
      }
    }

    # CANARY: small % canary first, bake, then full cutover
    dynamic "canary_configuration" {
      for_each = try(each.value.service.deployment_configuration.strategy, var.deployment_strategy_default) == "CANARY" ? [try(each.value.service.deployment_configuration.canary_configuration, {})] : []
      content {
        canary_percent              = try(canary_configuration.value.canary_percent, 10)
        canary_bake_time_in_minutes = try(canary_configuration.value.canary_bake_time_in_minutes, 10)
      }
    }

    # Lifecycle hooks — Lambda validation at deployment stages (non-ROLLING)
    dynamic "lifecycle_hook" {
      for_each = try(each.value.service.deployment_configuration.strategy, var.deployment_strategy_default) != "ROLLING" ? try(each.value.service.deployment_configuration.lifecycle_hooks, []) : []
      content {
        hook_target_arn  = lifecycle_hook.value.hook_target_arn
        role_arn         = lifecycle_hook.value.role_arn
        lifecycle_stages = lifecycle_hook.value.lifecycle_stages
        hook_details     = try(lifecycle_hook.value.hook_details, null)
      }
    }
  }

  # Networking
  network_configuration {
    security_groups  = try(each.value.service.security_groups, [])
    subnets          = try(each.value.service.subnets, [])
    assign_public_ip = try(each.value.service.assign_public_ip, false)
  }

  # ============================================================================
  # Load balancer
  # Per-service target groups (container_config[].service.target_groups) take
  # priority over the module-level var.target_groups fallback.
  # advanced_configuration enables ECS-native B/G, Linear, Canary traffic shifting.
  # ============================================================================
  dynamic "load_balancer" {
    for_each = var.load_balanced ? try(each.value.service.target_groups, var.target_groups) : []
    content {
      container_name   = try(load_balancer.value.container_name, "") != "" ? load_balancer.value.container_name : "${local.account_alias}-${each.key}-${var.container_name}"
      container_port   = lookup(load_balancer.value, "container_port", var.task_container_port)
      target_group_arn = lookup(load_balancer.value, "target_group_arn", null)

      # Advanced configuration for ECS-native B/G, Linear, Canary (provider >= 6.4.0)
      # Set alternate_target_group_arn + production_listener_rule in target_groups entry
      dynamic "advanced_configuration" {
        for_each = try(each.value.service.deployment_configuration.strategy, var.deployment_strategy_default) != "ROLLING" && try(load_balancer.value.alternate_target_group_arn, "") != "" ? [1] : []
        content {
          alternate_target_group_arn = load_balancer.value.alternate_target_group_arn
          production_listener_rule   = try(load_balancer.value.production_listener_rule, null)
          role_arn                   = try(each.value.service.deployment_configuration.ecs_alb_service_role_arn, null)
        }
      }
    }
  }

  # Service Connect (tier-to-tier communication via Cloud Map)
  dynamic "service_connect_configuration" {
    for_each = try(each.value.service.service_connect, null) != null ? [each.value.service.service_connect] : []
    content {
      enabled   = service_connect_configuration.value.enabled
      namespace = try(service_connect_configuration.value.namespace, var.service_connect_configuration.namespace)

      dynamic "log_configuration" {
        for_each = try(service_connect_configuration.value.log_configuration, null) != null ? [service_connect_configuration.value.log_configuration] : var.service_connect_configuration.log_configuration != null ? [var.service_connect_configuration.log_configuration] : []
        content {
          log_driver = log_configuration.value.log_driver
          options    = log_configuration.value.options

          dynamic "secret_option" {
            for_each = try(log_configuration.value.secret_options, [])
            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      dynamic "service" {
        for_each = try(service_connect_configuration.value.services, [])
        content {
          port_name             = service.value.port_name
          discovery_name        = try(service.value.discovery_name, null)
          ingress_port_override = try(service.value.ingress_port_override, null)

          dynamic "client_alias" {
            for_each = try(service.value.client_aliases, [])
            content {
              port     = client_alias.value.port
              dns_name = try(client_alias.value.dns_name, null)
            }
          }

          dynamic "timeout" {
            for_each = try(service.value.timeout, null) != null ? [service.value.timeout] : []
            content {
              idle_timeout_seconds        = try(timeout.value.idle_timeout_seconds, null)
              per_request_timeout_seconds = try(timeout.value.per_request_timeout_seconds, null)
            }
          }

          dynamic "tls" {
            for_each = try(service.value.tls, null) != null ? [service.value.tls] : []
            content {
              issuer_cert_authority {
                aws_pca_authority_arn = tls.value.issuer_cert_authority.aws_pca_authority_arn
              }
              kms_key  = try(tls.value.kms_key, null)
              role_arn = try(tls.value.role_arn, null)
            }
          }
        }
      }
    }
  }

  # Service registries (Cloud Map DNS-based discovery)
  dynamic "service_registries" {
    for_each = try(each.value.service.service_registries, [])
    content {
      registry_arn   = service_registries.value.registry_arn
      port           = try(service_registries.value.port, null)
      container_name = try(service_registries.value.container_name, null)
      container_port = try(service_registries.value.container_port, null)
    }
  }

  # Ordered placement strategy
  dynamic "ordered_placement_strategy" {
    for_each = try(each.value.service.ordered_placement_strategy, [])
    content {
      type  = ordered_placement_strategy.value.type
      field = try(ordered_placement_strategy.value.field, null)
    }
  }

  # Placement constraints
  dynamic "placement_constraints" {
    for_each = try(each.value.service.placement_constraints, [])
    content {
      type       = placement_constraints.value.type
      expression = try(placement_constraints.value.expression, null)
    }
  }

  # Capacity provider strategy (overrides launch_type when set)
  dynamic "capacity_provider_strategy" {
    for_each = try(each.value.service.capacity_provider_strategy, [])
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = try(capacity_provider_strategy.value.weight, null)
      base              = try(capacity_provider_strategy.value.base, null)
    }
  }

  lifecycle {
    # Auto Scaling manages desired_count; task_definition changes during B/G deployments
    ignore_changes = [desired_count, task_definition]
  }
}

########################################
# Target Groups must be created externally (e.g., ALB module)
# Pass ARNs via container_config[key].service.target_groups[].target_group_arn
# For B/G strategies also pass alternate_target_group_arn + production_listener_rule
########################################
