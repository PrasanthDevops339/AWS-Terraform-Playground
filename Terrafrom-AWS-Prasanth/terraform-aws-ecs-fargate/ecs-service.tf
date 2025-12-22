# ecs-service placeholder; add your service and load_balancer logic here
########################################
# ecs-service.tf
########################################

resource "aws_ecs_service" "main" {
  for_each = {
    for k, v in var.container_config : k => v
    if try(v.service.deployment_controller.type, "ECS") == "ECS"
  }

  name                  = "${local.account_alias}-${each.key}"
  cluster               = aws_ecs_cluster.main[0].id
  task_definition       = aws_ecs_task_definition.main[each.key].arn
  desired_count         = try(each.value.service.desired_count, 1)
  propagate_tags        = try(each.value.service.propagate_tags, "SERVICE")
  launch_type           = "FARGATE"
  platform_version      = try(each.value.service.platform_version, "LATEST")
  scheduling_strategy   = "REPLICA"
  enable_execute_command = try(each.value.service.enable_execute_command, false)
  force_new_deployment   = try(each.value.service.force_new_deployment, false)

  tags = merge(var.tags, {
    "Name" = "${local.account_alias}-${each.key}"
  })

  # Deployment controller configuration
  deployment_controller {
    type = try(each.value.service.deployment_controller.type, "ECS")
  }

  network_configuration {
    security_groups = try(each.value.service.security_groups, [])
    subnets         = try(each.value.service.subnets, [])
    assign_public_ip = try(each.value.service.assign_public_ip, false)
  }

  # Deployment configuration with circuit breaker and alarms
  deployment_configuration {
    maximum_percent         = try(each.value.service.deployment_configuration.maximum_percent, var.deployment_configuration.maximum_percent)
    minimum_healthy_percent = try(each.value.service.deployment_configuration.minimum_healthy_percent, var.deployment_configuration.minimum_healthy_percent)

    dynamic "deployment_circuit_breaker" {
      for_each = try(each.value.service.deployment_configuration.deployment_circuit_breaker, null) != null ? [each.value.service.deployment_configuration.deployment_circuit_breaker] : var.deployment_configuration.deployment_circuit_breaker != null ? [var.deployment_configuration.deployment_circuit_breaker] : []
      content {
        enable   = deployment_circuit_breaker.value.enable
        rollback = deployment_circuit_breaker.value.rollback
      }
    }

    dynamic "alarms" {
      for_each = try(each.value.service.deployment_configuration.alarms, null) != null ? [each.value.service.deployment_configuration.alarms] : var.deployment_configuration.alarms != null ? [var.deployment_configuration.alarms] : []
      content {
        enable      = alarms.value.enable
        rollback    = alarms.value.rollback
        alarm_names = alarms.value.alarm_names
      }
    }
  }

  # Service Connect Configuration
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
          port_name      = service.value.port_name
          discovery_name = try(service.value.discovery_name, null)
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
              idle_timeout_seconds    = try(timeout.value.idle_timeout_seconds, null)
              per_request_timeout_seconds = try(timeout.value.per_request_timeout_seconds, null)
            }
          }

          dynamic "tls" {
            for_each = try(service.value.tls, null) != null ? [service.value.tls] : []
            content {
              issuer_certificate_authority {
                aws_pca_authority_arn = tls.value.issuer_certificate_authority.aws_pca_authority_arn
              }
              kms_key                = try(tls.value.kms_key, null)
              role_arn              = try(tls.value.role_arn, null)
            }
          }
        }
      }
    }
  }

  # Service registries for service discovery
  dynamic "service_registries" {
    for_each = try(each.value.service.service_registries, [])
    content {
      registry_arn   = service_registries.value.registry_arn
      port           = try(service_registries.value.port, null)
      container_name = try(service_registries.value.container_name, null)
      container_port = try(service_registries.value.container_port, null)
    }
  }

  # Attach to an ALB/NLB target group when load balanced
  dynamic "load_balancer" {
    for_each = var.load_balanced ? var.target_groups : []
    content {
      container_name = (
        try(lookup(load_balancer.value, "container_name", ""), "") != ""
      ) ? lookup(load_balancer.value, "container_name", "")
        : "${local.account_alias}-${each.key}-${var.container_name}"

      container_port = lookup(load_balancer.value, "container_port", var.task_container_port)

      # Target Group must be provided by external ALB module. Pass its ARN here.
      target_group_arn = lookup(load_balancer.value, "target_group_arn", null)
    }
  }

  # Wait for service deployment completion
  wait_for_steady_state = try(each.value.service.wait_for_steady_state, false)

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

  # Capacity provider strategy
  dynamic "capacity_provider_strategy" {
    for_each = try(each.value.service.capacity_provider_strategy, [])
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight           = try(capacity_provider_strategy.value.weight, null)
      base             = try(capacity_provider_strategy.value.base, null)
    }
  }
}

########################################
# Target Groups must be created externally (e.g., ALB module)
########################################
