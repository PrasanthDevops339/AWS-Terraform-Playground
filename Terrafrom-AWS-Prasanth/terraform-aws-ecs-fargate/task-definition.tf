resource "aws_ecs_task_definition" "main" {
  for_each = var.container_config
  family   = "${local.account_alias}-${each.key}"

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu                      = try(each.value.task_definition.cpu, null)
  memory                   = try(each.value.task_definition.memory, null)
  task_role_arn            = try(each.value.task_definition.task_role_arn, null)
  execution_role_arn       = try(each.value.task_definition.execution_role_arn, null)

  # If a complete container_definition JSON was provided, use it directly.
  # Otherwise, synthesize one from common fields.
  container_definitions = try(each.value.task_definition.container_definition, null) != null ?
    each.value.task_definition.container_definition :
    jsonencode([{
      name  = try(each.value.container_name, "${local.account_alias}-${each.key}-${var.container_name}")
      image = try(each.value.task_definition.image, null)
      cpu   = try(each.value.task_definition.cpu, null)
      memory               = try(each.value.task_definition.memory, null)
      memoryReservation    = try(each.value.task_definition.memoryReservation, null)

      portMappings = [{
        containerPort = try(each.value.task_definition.container_port, null)
        hostPort      = try(each.value.task_definition.host_port, null)
      }]

      environment          = try(each.value.task_definition.envvars, null)
      secrets              = try(each.value.task_definition.secrets, null)
      credentialSpecs      = try(each.value.task_definition.credentialSpecs, null)
      command              = try(each.value.task_definition.command, null)
      environmentFiles     = try(each.value.task_definition.environmentFiles, null)
      disableNetworking    = try(each.value.task_definition.disableNetworking, null)
      dnsSearchDomains     = try(each.value.task_definition.dns_search_domains, null)
      dnsServers           = try(each.value.task_definition.dns_servers, null)
      dockerLabels         = try(each.value.task_definition.docker_labels, null)
      dockerSecurityOptions= try(each.value.task_definition.docker_security_options, null)
      linuxParameters      = try(each.value.task_definition.linuxParameters, null)
      links                = try(each.value.task_definition.links, null)
      entryPoint           = try(each.value.task_definition.entrypoint, null)
      hostname             = try(each.value.task_definition.hostname, null)
      healthCheck          = try(each.value.task_definition.healthcheck, null)
      essential            = try(each.value.task_definition.essential, null)
      interactive          = try(each.value.task_definition.interactive, null)
      readonlyRootFilesystem = try(each.value.task_definition.readonlyRootFilesystem, null)

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = try(each.value.task_definition.task_log_group_name, null)
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "/${each.key}"
          mode                  = try(each.value.task_definition.mode, null)
          max-buffer-size       = try(each.value.task_definition.max-buffer_size, null)
        }
      }

      dependsOn = try(each.value.task_definition.dependsOn, null)
    }])

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
          file_system_id         = lookup(efs_volume_configuration.value, "file_system_id", null)
          root_directory         = lookup(efs_volume_configuration.value, "root_directory", null)
          transit_encryption     = lookup(efs_volume_configuration.value, "transit_encryption", null)
          transit_encryption_port= lookup(efs_volume_configuration.value, "transit_encryption_port", null)

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

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}" })
}
