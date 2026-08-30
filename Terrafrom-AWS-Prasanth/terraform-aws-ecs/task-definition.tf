locals {
  task_definition_port_mappings = {
    for service_name, service_config in var.container_config :
    service_name => try(
      service_config.task_definition.port_mappings,
      try(
        service_config.task_definition.portMappings,
        try(service_config.task_definition.container_port, null) != null ? [{
          name          = try(service_config.task_definition.port_name, null)
          containerPort = service_config.task_definition.container_port
          hostPort      = try(service_config.task_definition.host_port, null)
          protocol      = try(service_config.task_definition.port_protocol, null)
          appProtocol   = try(service_config.task_definition.app_protocol, null)
        }] : null
      )
    )
  }

  task_definition_rendered_container_definitions = {
    for service_name, service_config in var.container_config :
    service_name => (
      try(service_config.task_definition.container_definition, null) != null
      ? service_config.task_definition.container_definition
      : jsonencode([{
        name              = try(service_config.container_name, "${local.account_alias}-${service_name}-${var.container_name}")
        image             = try(service_config.task_definition.image, null)
        cpu               = try(service_config.task_definition.cpu, null)
        memory            = try(service_config.task_definition.memory, null)
        memoryReservation = try(service_config.task_definition.memoryReservation, null)

        portMappings = local.task_definition_port_mappings[service_name]

        environment            = try(service_config.task_definition.environment, try(service_config.task_definition.envvars, null))
        secrets                = try(service_config.task_definition.secrets, null)
        credentialSpecs        = try(service_config.task_definition.credentialSpecs, null)
        command                = try(service_config.task_definition.command, null)
        environmentFiles       = try(service_config.task_definition.environmentFiles, null)
        disableNetworking      = try(service_config.task_definition.disableNetworking, null)
        dnsSearchDomains       = try(service_config.task_definition.dns_search_domains, null)
        dnsServers             = try(service_config.task_definition.dns_servers, null)
        dockerLabels           = try(service_config.task_definition.docker_labels, null)
        dockerSecurityOptions  = try(service_config.task_definition.docker_security_options, null)
        linuxParameters        = try(service_config.task_definition.linuxParameters, null)
        links                  = try(service_config.task_definition.links, null)
        entryPoint             = try(service_config.task_definition.entrypoint, try(service_config.task_definition.entry_point, null))
        hostname               = try(service_config.task_definition.hostname, null)
        healthCheck            = try(service_config.task_definition.health_check, try(service_config.task_definition.healthcheck, try(service_config.task_definition.healthCheck, null)))
        essential              = try(service_config.task_definition.essential, null)
        interactive            = try(service_config.task_definition.interactive, null)
        readonlyRootFilesystem = try(service_config.task_definition.readonlyRootFilesystem, null)
        mountPoints            = try(service_config.task_definition.mount_points, try(service_config.task_definition.mountPoints, null))
        volumesFrom            = try(service_config.task_definition.volumes_from, try(service_config.task_definition.volumesFrom, null))
        firelensConfiguration  = try(service_config.task_definition.firelens_configuration, try(service_config.task_definition.firelensConfiguration, null))

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group = try(service_config.task_definition.task_log_group_name, null)
            # aws_region.name is deprecated in AWS provider 6.x; .region replaces it.
            awslogs-region        = local.region
            awslogs-stream-prefix = "/${service_name}"
            mode                  = try(service_config.task_definition.mode, null)
            max-buffer-size = try(
              service_config.task_definition.max_buffer_size,
              try(service_config.task_definition["max-buffer-size"],
                try(service_config.task_definition["max-buffer_size"], null)
              )
            )
          }
        }

        dependsOn = try(service_config.task_definition.dependsOn, null)
      }])
    )
  }
}

resource "aws_ecs_task_definition" "main" {
  for_each = var.container_config
  family   = "${local.account_alias}-${each.key}"

  # Derived from the service's launch type rather than hardcoded, so the same
  # module registers Fargate, EC2 and ECS Anywhere task definitions.
  requires_compatibilities = local.svc_resolved[each.key].requires_compatibilities
  network_mode             = local.svc_resolved[each.key].network_mode

  # Task-level sizing is mandatory on Fargate. On EC2 it is optional, since
  # containers may declare their own cpu/memory limits instead.
  cpu                = try(each.value.task_definition.cpu, null)
  memory             = try(each.value.task_definition.memory, null)
  task_role_arn      = try(each.value.task_definition.task_role_arn, null)
  execution_role_arn = try(each.value.task_definition.execution_role_arn, null)

  # Namespace sharing and fault injection are EC2-only; Fargate rejects them.
  pid_mode = local.svc_resolved[each.key].launch_type == "EC2" ? try(each.value.task_definition.pid_mode, null) : null
  ipc_mode = local.svc_resolved[each.key].launch_type == "EC2" ? try(each.value.task_definition.ipc_mode, null) : null

  track_latest = try(each.value.task_definition.track_latest, false)
  skip_destroy = try(each.value.task_definition.skip_destroy, false)

  # EC2 task placement rules, evaluated when ECS picks a container instance.
  dynamic "placement_constraints" {
    for_each = try(each.value.task_definition.placement_constraints, [])
    content {
      type       = placement_constraints.value.type
      expression = try(placement_constraints.value.expression, null)
    }
  }

  # Keep the resource body simple; render the JSON in locals so both Terraform
  # and IDE language servers have an easier time parsing it.
  container_definitions = local.task_definition_rendered_container_definitions[each.key]

  runtime_platform {
    operating_system_family = try(each.value.task_definition.operating_system_family, "LINUX")
    cpu_architecture        = try(each.value.task_definition.cpu_architecture, "X86_64")
  }

  dynamic "ephemeral_storage" {
    for_each = try(each.value.task_definition.ephemeral_storage, null) != null ? [each.value.task_definition.ephemeral_storage] : []
    content {
      size_in_gib = ephemeral_storage.value.size_in_gib
    }
  }

  dynamic "volume" {
    for_each = var.efs_volumes
    content {
      name      = volume.value.name
      host_path = lookup(volume.value, "host_path", null)

      dynamic "efs_volume_configuration" {
        for_each = lookup(volume.value, "efs_volume_configuration", [])
        content {
          file_system_id          = lookup(efs_volume_configuration.value, "file_system_id", null)
          root_directory          = lookup(efs_volume_configuration.value, "root_directory", null)
          transit_encryption      = lookup(efs_volume_configuration.value, "transit_encryption", null)
          transit_encryption_port = lookup(efs_volume_configuration.value, "transit_encryption_port", null)

          dynamic "authorization_config" {
            for_each = length(lookup(efs_volume_configuration.value, "authorization_config", {})) == 0 ? [] : [lookup(efs_volume_configuration.value, "authorization_config", {})]
            content {
              access_point_id = lookup(authorization_config.value, "access_point_id", null)
              iam             = lookup(authorization_config.value, "iam", null)
            }
          }
        }
      }
    }
  }

  # Docker volume plugins - EC2 launch type only, Fargate has no Docker daemon
  # for the plugin to bind to.
  dynamic "volume" {
    for_each = local.svc_resolved[each.key].launch_type == "EC2" ? try(each.value.task_definition.docker_volumes, []) : []
    content {
      name = volume.value.name

      docker_volume_configuration {
        scope  = try(volume.value.scope, "task")
        driver = try(volume.value.driver, "local")
        # autoprovision is only valid on shared-scope volumes.
        autoprovision = try(volume.value.scope, "task") == "task" ? null : try(volume.value.autoprovision, false)
        driver_opts   = try(volume.value.driver_opts, null)
        labels        = try(volume.value.labels, null)
      }
    }
  }

  # Bind mounts. host_path pins the mount to a path on the container instance
  # and is therefore EC2-only; on Fargate the volume must stay empty.
  dynamic "volume" {
    for_each = try(each.value.task_definition.bind_mount_volumes, [])
    content {
      name      = volume.value.name
      host_path = local.svc_resolved[each.key].launch_type == "EC2" ? try(volume.value.host_path, null) : null
    }
  }

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}" })
}
