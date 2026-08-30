########################################
# ecs-service.tf
#
# ECS-controller services. The EXTERNAL controller lives in
# ecs-service-external.tf, because lifecycle.ignore_changes cannot be computed
# and each controller needs a different one.
#
# Deployment types covered here:
#   deployment_configuration.strategy = ROLLING     in-place rolling update
#                                     = BLUE_GREEN  full green fleet, then cut
#                                     = LINEAR      shift step_percent at a time
#                                     = CANARY      small canary, bake, then all
#
#   scheduling_strategy = REPLICA  n tasks, optionally autoscaled
#                       = DAEMON   one task per container instance (EC2 only)
#
# Launch types covered here: FARGATE, EC2 and EXTERNAL (ECS Anywhere), selected
# per service with service.launch_type or a capacity_provider_strategy.
#
# Two resources exist below, identical apart from for_each and lifecycle:
#
#   aws_ecs_service.main                 Terraform owns the task definition and
#                                        performs the deployment
#   aws_ecs_service.main_unmanaged_td    an external pipeline rolls the image;
#                                        opt in per service with
#                                        service.ignore_task_definition_changes
########################################

resource "aws_ecs_service" "main" {
  for_each = local.services_ecs_managed_td

  name            = "${local.account_alias}-${each.key}"
  cluster         = local.cluster_id
  task_definition = aws_ecs_task_definition.main[each.key].arn

  # DAEMON places exactly one task per container instance, so a desired count
  # is rejected by the API.
  desired_count = local.svc_resolved[each.key].is_daemon ? null : try(each.value.service.desired_count, 1)

  scheduling_strategy = local.svc_resolved[each.key].scheduling_strategy
  propagate_tags      = try(each.value.service.propagate_tags, "SERVICE")

  # launch_type and capacity_provider_strategy are mutually exclusive; the
  # derivation in locals.tf guarantees only one of them is ever set.
  launch_type      = local.svc_resolved[each.key].effective_launch_type
  platform_version = local.svc_resolved[each.key].platform_version

  enable_execute_command  = try(each.value.service.enable_execute_command, false)
  enable_ecs_managed_tags = try(each.value.service.enable_ecs_managed_tags, true)
  force_new_deployment    = try(each.value.service.force_new_deployment, false)
  wait_for_steady_state   = try(each.value.service.wait_for_steady_state, false)
  force_delete            = try(each.value.service.force_delete, null)

  availability_zone_rebalancing = try(each.value.service.availability_zone_rebalancing, null)

  health_check_grace_period_seconds = var.load_balanced && length(try(each.value.service.target_groups, var.target_groups)) > 0 ? try(each.value.service.health_check_grace_period_seconds, null) : null

  tags = merge(var.tags, {
    "Name" = "${local.account_alias}-${each.key}"
  })

  deployment_controller {
    type = "ECS"
  }

  # ============================================================================
  # Rolling deployment thresholds - top-level in AWS provider 6.x.
  # Both are rejected for DAEMON services.
  # ============================================================================
  deployment_maximum_percent = (
    local.svc_resolved[each.key].is_daemon
    ? null
    : try(each.value.service.deployment_configuration.maximum_percent, var.deployment_configuration.maximum_percent)
  )
  deployment_minimum_healthy_percent = try(each.value.service.deployment_configuration.minimum_healthy_percent, var.deployment_configuration.minimum_healthy_percent)

  dynamic "deployment_circuit_breaker" {
    for_each = try(each.value.service.deployment_configuration.deployment_circuit_breaker, null) != null ? [each.value.service.deployment_configuration.deployment_circuit_breaker] : var.deployment_configuration.deployment_circuit_breaker != null ? [var.deployment_configuration.deployment_circuit_breaker] : []
    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  # ============================================================================
  # Alarm-based rollback.
  #
  # This is a TOP-LEVEL block on aws_ecs_service. It is not part of
  # deployment_configuration - nesting it there fails to validate.
  # ============================================================================
  dynamic "alarms" {
    for_each = try(each.value.service.deployment_configuration.alarms, null) != null ? [each.value.service.deployment_configuration.alarms] : var.deployment_configuration.alarms != null ? [var.deployment_configuration.alarms] : []
    content {
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
      alarm_names = alarms.value.alarm_names
    }
  }

  # ============================================================================
  # ECS-native deployment strategy (AWS provider >= 6.4.0, no CodeDeploy)
  # ============================================================================
  deployment_configuration {
    strategy = local.svc_resolved[each.key].deployment_strategy

    # Bake time is the soak on the new revision before the old one is torn
    # down, and only applies once traffic is actually being shifted.
    bake_time_in_minutes = local.svc_resolved[each.key].shifts_traffic ? try(each.value.service.deployment_configuration.bake_time_in_minutes, 5) : null

    # LINEAR: shift a fixed percentage per step, pausing between steps.
    dynamic "linear_configuration" {
      for_each = local.svc_resolved[each.key].deployment_strategy == "LINEAR" ? [try(each.value.service.deployment_configuration.linear_configuration, {})] : []
      content {
        step_percent              = try(linear_configuration.value.step_percent, 25)
        step_bake_time_in_minutes = try(linear_configuration.value.step_bake_time_in_minutes, 5)
      }
    }

    # CANARY: shift a small slice, hold, then move the remainder in one step.
    dynamic "canary_configuration" {
      for_each = local.svc_resolved[each.key].deployment_strategy == "CANARY" ? [try(each.value.service.deployment_configuration.canary_configuration, {})] : []
      content {
        canary_percent              = try(canary_configuration.value.canary_percent, 10)
        canary_bake_time_in_minutes = try(canary_configuration.value.canary_bake_time_in_minutes, 10)
      }
    }

    # Lambda hooks fire between traffic-shifting stages.
    dynamic "lifecycle_hook" {
      for_each = local.svc_resolved[each.key].shifts_traffic ? try(each.value.service.deployment_configuration.lifecycle_hooks, []) : []
      content {
        hook_target_arn  = lifecycle_hook.value.hook_target_arn
        role_arn         = try(coalesce(try(lifecycle_hook.value.role_arn, null), local.infrastructure_iam_role_arns[each.key]), null)
        lifecycle_stages = lifecycle_hook.value.lifecycle_stages
        hook_details     = try(lifecycle_hook.value.hook_details, null)
      }
    }
  }

  # ============================================================================
  # Networking - awsvpc only.
  #
  # bridge and host tasks share the container instance ENI, and ECS rejects a
  # network_configuration for them.
  # ============================================================================
  dynamic "network_configuration" {
    for_each = local.svc_resolved[each.key].network_mode == "awsvpc" ? [1] : []
    content {
      security_groups = try(each.value.service.security_groups, [])
      subnets         = try(each.value.service.subnets, [])
      # An ENI setting, so awsvpc only.
      assign_public_ip = try(each.value.service.assign_public_ip, false)
    }
  }

  # ============================================================================
  # Load balancer
  #
  # Per-service target_groups take priority over the module-level fallback.
  # advanced_configuration drives ECS-native BLUE_GREEN / LINEAR / CANARY
  # traffic shifting.
  # ============================================================================
  dynamic "load_balancer" {
    for_each = var.load_balanced ? try(each.value.service.target_groups, var.target_groups) : []
    content {
      container_name   = try(load_balancer.value.container_name, "") != "" ? load_balancer.value.container_name : "${local.account_alias}-${each.key}-${var.container_name}"
      container_port   = lookup(load_balancer.value, "container_port", var.task_container_port)
      target_group_arn = lookup(load_balancer.value, "target_group_arn", null)

      dynamic "advanced_configuration" {
        for_each = local.svc_resolved[each.key].shifts_traffic && try(load_balancer.value.alternate_target_group_arn, "") != "" ? [1] : []
        content {
          alternate_target_group_arn = load_balancer.value.alternate_target_group_arn
          production_listener_rule   = try(load_balancer.value.production_listener_rule, null)
          # Optional second rule for smoke-testing green before the cutover.
          test_listener_rule = try(load_balancer.value.test_listener_rule, null)
          # Required by the provider. Falls back to the infrastructure role the
          # module creates, so a BLUE_GREEN service needs no extra wiring.
          role_arn = local.infrastructure_iam_role_arns[each.key]
        }
      }
    }
  }

  dynamic "vpc_lattice_configurations" {
    for_each = try(each.value.service.vpc_lattice_configurations, [])
    content {
      role_arn         = try(coalesce(try(vpc_lattice_configurations.value.role_arn, null), local.infrastructure_iam_role_arns[each.key]), null)
      target_group_arn = vpc_lattice_configurations.value.target_group_arn
      port_name        = vpc_lattice_configurations.value.port_name
    }
  }

  # ============================================================================
  # EBS volumes attached at task launch. Requires a matching task definition
  # volume with configure_at_launch = true.
  # ============================================================================
  dynamic "volume_configuration" {
    for_each = try(each.value.service.ebs_volumes, [])
    content {
      name = volume_configuration.value.name

      managed_ebs_volume {
        role_arn         = try(coalesce(try(volume_configuration.value.role_arn, null), local.infrastructure_iam_role_arns[each.key]), null)
        size_in_gb       = try(volume_configuration.value.size_in_gb, null)
        volume_type      = try(volume_configuration.value.volume_type, "gp3")
        encrypted        = try(volume_configuration.value.encrypted, true)
        kms_key_id       = try(volume_configuration.value.kms_key_id, null)
        iops             = try(volume_configuration.value.iops, null)
        throughput       = try(volume_configuration.value.throughput, null)
        snapshot_id      = try(volume_configuration.value.snapshot_id, null)
        file_system_type = try(volume_configuration.value.file_system_type, "xfs")
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

  # ============================================================================
  # Placement - EC2 only. Fargate has no container instances to place across,
  # and rejects an ordered_placement_strategy.
  # ============================================================================
  dynamic "ordered_placement_strategy" {
    for_each = local.svc_resolved[each.key].launch_type == "EC2" ? try(each.value.service.ordered_placement_strategy, []) : []
    content {
      type  = ordered_placement_strategy.value.type
      field = try(ordered_placement_strategy.value.field, null)
    }
  }

  dynamic "placement_constraints" {
    for_each = try(each.value.service.placement_constraints, [])
    content {
      type       = placement_constraints.value.type
      expression = try(placement_constraints.value.expression, null)
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.svc_resolved[each.key].capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = try(capacity_provider_strategy.value.weight, null)
      base              = try(capacity_provider_strategy.value.base, null)
    }
  }

  lifecycle {
    # desired_count is surrendered to Application Auto Scaling.
    #
    # task_definition is deliberately NOT ignored: Terraform performs the
    # deployment for these services, and ignoring it would make every image
    # bump a silent no-op. ECS-native BLUE_GREEN / LINEAR / CANARY still work,
    # because ECS reads the new revision from the service update itself.
    ignore_changes = [desired_count]
  }

  # EC2 tasks cannot be placed until container instances are registered, and
  # ECS cannot shift traffic until the infrastructure role can touch the ALB.
  depends_on = [
    aws_ecs_cluster_capacity_providers.main,
    aws_iam_role_policy_attachment.infrastructure_load_balancer,
    aws_iam_role_policy_attachment.infrastructure_volumes,
    aws_iam_role_policy_attachment.infrastructure_vpc_lattice,
  ]
}

resource "aws_ecs_service" "main_unmanaged_td" {
  for_each = local.services_ecs_unmanaged_td

  name            = "${local.account_alias}-${each.key}"
  cluster         = local.cluster_id
  task_definition = aws_ecs_task_definition.main[each.key].arn

  # DAEMON places exactly one task per container instance, so a desired count
  # is rejected by the API.
  desired_count = local.svc_resolved[each.key].is_daemon ? null : try(each.value.service.desired_count, 1)

  scheduling_strategy = local.svc_resolved[each.key].scheduling_strategy
  propagate_tags      = try(each.value.service.propagate_tags, "SERVICE")

  # launch_type and capacity_provider_strategy are mutually exclusive; the
  # derivation in locals.tf guarantees only one of them is ever set.
  launch_type      = local.svc_resolved[each.key].effective_launch_type
  platform_version = local.svc_resolved[each.key].platform_version

  enable_execute_command  = try(each.value.service.enable_execute_command, false)
  enable_ecs_managed_tags = try(each.value.service.enable_ecs_managed_tags, true)
  force_new_deployment    = try(each.value.service.force_new_deployment, false)
  wait_for_steady_state   = try(each.value.service.wait_for_steady_state, false)
  force_delete            = try(each.value.service.force_delete, null)

  availability_zone_rebalancing = try(each.value.service.availability_zone_rebalancing, null)

  health_check_grace_period_seconds = var.load_balanced && length(try(each.value.service.target_groups, var.target_groups)) > 0 ? try(each.value.service.health_check_grace_period_seconds, null) : null

  tags = merge(var.tags, {
    "Name" = "${local.account_alias}-${each.key}"
  })

  deployment_controller {
    type = "ECS"
  }

  # ============================================================================
  # Rolling deployment thresholds - top-level in AWS provider 6.x.
  # Both are rejected for DAEMON services.
  # ============================================================================
  deployment_maximum_percent = (
    local.svc_resolved[each.key].is_daemon
    ? null
    : try(each.value.service.deployment_configuration.maximum_percent, var.deployment_configuration.maximum_percent)
  )
  deployment_minimum_healthy_percent = try(each.value.service.deployment_configuration.minimum_healthy_percent, var.deployment_configuration.minimum_healthy_percent)

  dynamic "deployment_circuit_breaker" {
    for_each = try(each.value.service.deployment_configuration.deployment_circuit_breaker, null) != null ? [each.value.service.deployment_configuration.deployment_circuit_breaker] : var.deployment_configuration.deployment_circuit_breaker != null ? [var.deployment_configuration.deployment_circuit_breaker] : []
    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  # ============================================================================
  # Alarm-based rollback.
  #
  # This is a TOP-LEVEL block on aws_ecs_service. It is not part of
  # deployment_configuration - nesting it there fails to validate.
  # ============================================================================
  dynamic "alarms" {
    for_each = try(each.value.service.deployment_configuration.alarms, null) != null ? [each.value.service.deployment_configuration.alarms] : var.deployment_configuration.alarms != null ? [var.deployment_configuration.alarms] : []
    content {
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
      alarm_names = alarms.value.alarm_names
    }
  }

  # ============================================================================
  # ECS-native deployment strategy (AWS provider >= 6.4.0, no CodeDeploy)
  # ============================================================================
  deployment_configuration {
    strategy = local.svc_resolved[each.key].deployment_strategy

    # Bake time is the soak on the new revision before the old one is torn
    # down, and only applies once traffic is actually being shifted.
    bake_time_in_minutes = local.svc_resolved[each.key].shifts_traffic ? try(each.value.service.deployment_configuration.bake_time_in_minutes, 5) : null

    # LINEAR: shift a fixed percentage per step, pausing between steps.
    dynamic "linear_configuration" {
      for_each = local.svc_resolved[each.key].deployment_strategy == "LINEAR" ? [try(each.value.service.deployment_configuration.linear_configuration, {})] : []
      content {
        step_percent              = try(linear_configuration.value.step_percent, 25)
        step_bake_time_in_minutes = try(linear_configuration.value.step_bake_time_in_minutes, 5)
      }
    }

    # CANARY: shift a small slice, hold, then move the remainder in one step.
    dynamic "canary_configuration" {
      for_each = local.svc_resolved[each.key].deployment_strategy == "CANARY" ? [try(each.value.service.deployment_configuration.canary_configuration, {})] : []
      content {
        canary_percent              = try(canary_configuration.value.canary_percent, 10)
        canary_bake_time_in_minutes = try(canary_configuration.value.canary_bake_time_in_minutes, 10)
      }
    }

    # Lambda hooks fire between traffic-shifting stages.
    dynamic "lifecycle_hook" {
      for_each = local.svc_resolved[each.key].shifts_traffic ? try(each.value.service.deployment_configuration.lifecycle_hooks, []) : []
      content {
        hook_target_arn  = lifecycle_hook.value.hook_target_arn
        role_arn         = try(coalesce(try(lifecycle_hook.value.role_arn, null), local.infrastructure_iam_role_arns[each.key]), null)
        lifecycle_stages = lifecycle_hook.value.lifecycle_stages
        hook_details     = try(lifecycle_hook.value.hook_details, null)
      }
    }
  }

  # ============================================================================
  # Networking - awsvpc only.
  #
  # bridge and host tasks share the container instance ENI, and ECS rejects a
  # network_configuration for them.
  # ============================================================================
  dynamic "network_configuration" {
    for_each = local.svc_resolved[each.key].network_mode == "awsvpc" ? [1] : []
    content {
      security_groups = try(each.value.service.security_groups, [])
      subnets         = try(each.value.service.subnets, [])
      # An ENI setting, so awsvpc only.
      assign_public_ip = try(each.value.service.assign_public_ip, false)
    }
  }

  # ============================================================================
  # Load balancer
  #
  # Per-service target_groups take priority over the module-level fallback.
  # advanced_configuration drives ECS-native BLUE_GREEN / LINEAR / CANARY
  # traffic shifting.
  # ============================================================================
  dynamic "load_balancer" {
    for_each = var.load_balanced ? try(each.value.service.target_groups, var.target_groups) : []
    content {
      container_name   = try(load_balancer.value.container_name, "") != "" ? load_balancer.value.container_name : "${local.account_alias}-${each.key}-${var.container_name}"
      container_port   = lookup(load_balancer.value, "container_port", var.task_container_port)
      target_group_arn = lookup(load_balancer.value, "target_group_arn", null)

      dynamic "advanced_configuration" {
        for_each = local.svc_resolved[each.key].shifts_traffic && try(load_balancer.value.alternate_target_group_arn, "") != "" ? [1] : []
        content {
          alternate_target_group_arn = load_balancer.value.alternate_target_group_arn
          production_listener_rule   = try(load_balancer.value.production_listener_rule, null)
          # Optional second rule for smoke-testing green before the cutover.
          test_listener_rule = try(load_balancer.value.test_listener_rule, null)
          # Required by the provider. Falls back to the infrastructure role the
          # module creates, so a BLUE_GREEN service needs no extra wiring.
          role_arn = local.infrastructure_iam_role_arns[each.key]
        }
      }
    }
  }

  dynamic "vpc_lattice_configurations" {
    for_each = try(each.value.service.vpc_lattice_configurations, [])
    content {
      role_arn         = try(coalesce(try(vpc_lattice_configurations.value.role_arn, null), local.infrastructure_iam_role_arns[each.key]), null)
      target_group_arn = vpc_lattice_configurations.value.target_group_arn
      port_name        = vpc_lattice_configurations.value.port_name
    }
  }

  # ============================================================================
  # EBS volumes attached at task launch. Requires a matching task definition
  # volume with configure_at_launch = true.
  # ============================================================================
  dynamic "volume_configuration" {
    for_each = try(each.value.service.ebs_volumes, [])
    content {
      name = volume_configuration.value.name

      managed_ebs_volume {
        role_arn         = try(coalesce(try(volume_configuration.value.role_arn, null), local.infrastructure_iam_role_arns[each.key]), null)
        size_in_gb       = try(volume_configuration.value.size_in_gb, null)
        volume_type      = try(volume_configuration.value.volume_type, "gp3")
        encrypted        = try(volume_configuration.value.encrypted, true)
        kms_key_id       = try(volume_configuration.value.kms_key_id, null)
        iops             = try(volume_configuration.value.iops, null)
        throughput       = try(volume_configuration.value.throughput, null)
        snapshot_id      = try(volume_configuration.value.snapshot_id, null)
        file_system_type = try(volume_configuration.value.file_system_type, "xfs")
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

  # ============================================================================
  # Placement - EC2 only. Fargate has no container instances to place across,
  # and rejects an ordered_placement_strategy.
  # ============================================================================
  dynamic "ordered_placement_strategy" {
    for_each = local.svc_resolved[each.key].launch_type == "EC2" ? try(each.value.service.ordered_placement_strategy, []) : []
    content {
      type  = ordered_placement_strategy.value.type
      field = try(ordered_placement_strategy.value.field, null)
    }
  }

  dynamic "placement_constraints" {
    for_each = try(each.value.service.placement_constraints, [])
    content {
      type       = placement_constraints.value.type
      expression = try(placement_constraints.value.expression, null)
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.svc_resolved[each.key].capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = try(capacity_provider_strategy.value.weight, null)
      base              = try(capacity_provider_strategy.value.base, null)
    }
  }

  lifecycle {
    # For services whose image is rolled by a pipeline outside Terraform.
    # Opt in with service.ignore_task_definition_changes = true.
    ignore_changes = [desired_count, task_definition]
  }

  # EC2 tasks cannot be placed until container instances are registered, and
  # ECS cannot shift traffic until the infrastructure role can touch the ALB.
  depends_on = [
    aws_ecs_cluster_capacity_providers.main,
    aws_iam_role_policy_attachment.infrastructure_load_balancer,
    aws_iam_role_policy_attachment.infrastructure_volumes,
    aws_iam_role_policy_attachment.infrastructure_vpc_lattice,
  ]
}

########################################
# Target groups are created externally (e.g. by the ALB module) and passed in
# as ARNs via container_config[key].service.target_groups[].
#
# For BLUE_GREEN / LINEAR / CANARY each entry also needs:
#   alternate_target_group_arn  the green target group
#   production_listener_rule    the rule ECS reweights
#   test_listener_rule          optional, for pre-cutover validation
########################################
