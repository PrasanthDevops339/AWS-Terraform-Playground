################################################################################
# Locals
################################################################################

locals {
  cluster_name = var.create_cluster ? (var.cluster_name != "" ? var.cluster_name : var.name) : ""
  cluster_arn  = var.create_cluster ? aws_ecs_cluster.this[0].arn : var.cluster_arn
  cluster_id   = var.create_cluster ? aws_ecs_cluster.this[0].id : var.cluster_arn

  default_tags = merge(var.tags, {
    Module      = "terraform-aws-ecs-fargate-complete"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })

  # Per-service: container definitions JSON with auto-injected CloudWatch log config
  container_definitions_json = {
    for svc_name, svc in var.services : svc_name => jsonencode([
      for cd in svc.container_definitions : merge(cd, {
        logConfiguration = try(cd.logConfiguration, null) != null ? cd.logConfiguration : (
          svc.create_cloudwatch_log_group ? {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = svc.cloudwatch_log_group_name != "" ? svc.cloudwatch_log_group_name : "/ecs/${var.name}/${svc_name}"
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = try(cd.name, "ecs")
            }
          } : null
        )
      })
    ])
  }

  # Resolved log group name per service
  log_group_name = {
    for svc_name, svc in var.services : svc_name =>
    svc.cloudwatch_log_group_name != "" ? svc.cloudwatch_log_group_name : "/ecs/${var.name}/${svc_name}"
  }

  ##############################################################################
  # Filtered service maps — drive conditional for_each on optional resources
  ##############################################################################

  log_group_services = {
    for k, svc in var.services : k => svc if svc.create_cloudwatch_log_group
  }

  exec_log_services = {
    for k, svc in var.services : k => svc
    if svc.enable_execute_command && var.execute_command_logging == "OVERRIDE"
  }

  sg_services = {
    for k, svc in var.services : k => svc if svc.create_security_group
  }

  task_exec_role_services = {
    for k, svc in var.services : k => svc if svc.create_task_execution_role
  }

  task_exec_secrets_services = {
    for k, svc in var.services : k => svc
    if svc.create_task_execution_role && length(svc.secrets_arns) > 0
  }

  task_exec_ecr_services = {
    for k, svc in var.services : k => svc
    if svc.create_task_execution_role && length(svc.ecr_repository_arns) > 0
  }

  task_role_services = {
    for k, svc in var.services : k => svc if svc.create_task_role
  }

  task_exec_cmd_services = {
    for k, svc in var.services : k => svc
    if svc.create_task_role && svc.enable_execute_command
  }

  green_tg_services = {
    for k, svc in var.services : k => svc if svc.create_green_target_group
  }

  ecs_alb_services = {
    for k, svc in var.services : k => svc
    if svc.create_ecs_alb_service_role && svc.deployment_strategy != "ROLLING"
  }

  autoscaling_services = {
    for k, svc in var.services : k => svc if svc.autoscaling.enabled
  }

  cpu_autoscaling_services = {
    for k, svc in var.services : k => svc
    if svc.autoscaling.enabled && svc.autoscaling.cpu_target != null
  }

  memory_autoscaling_services = {
    for k, svc in var.services : k => svc
    if svc.autoscaling.enabled && svc.autoscaling.memory_target != null
  }

  alb_autoscaling_services = {
    for k, svc in var.services : k => svc
    if svc.autoscaling.enabled && svc.autoscaling.alb_request_count_target != null
  }

  alarm_services = {
    for k, svc in var.services : k => svc if svc.enable_cloudwatch_alarms
  }

  sd_services = {
    for k, svc in var.services : k => svc if svc.service_discovery.enabled
  }

  ##############################################################################
  # Flattened maps for nested for_each (SG rules, IAM policies, scaling actions)
  # Key format: "<svc_name>-<idx_or_name>" to guarantee uniqueness across tiers
  ##############################################################################

  sg_ingress_rules = merge([
    for svc_name, svc in var.services : {
      for idx, rule in svc.security_group_ingress_rules :
      "${svc_name}-${idx}" => merge(rule, { svc_name = svc_name })
    } if svc.create_security_group
  ]...)

  sg_egress_rules = merge([
    for svc_name, svc in var.services : {
      for idx, rule in svc.security_group_egress_rules :
      "${svc_name}-${idx}" => merge(rule, { svc_name = svc_name })
    } if svc.create_security_group
  ]...)

  task_exec_additional = merge([
    for svc_name, svc in var.services : {
      for arn in svc.task_execution_role_additional_policies :
      "${svc_name}__${replace(arn, "/", "_")}" => { svc_name = svc_name, policy_arn = arn }
    } if svc.create_task_execution_role
  ]...)

  task_exec_inline = merge([
    for svc_name, svc in var.services : {
      for p in svc.task_execution_role_inline_policies :
      "${svc_name}-${p.name}" => merge(p, { svc_name = svc_name })
    } if svc.create_task_execution_role
  ]...)

  task_additional = merge([
    for svc_name, svc in var.services : {
      for arn in svc.task_role_additional_policies :
      "${svc_name}__${replace(arn, "/", "_")}" => { svc_name = svc_name, policy_arn = arn }
    } if svc.create_task_role
  ]...)

  task_inline = merge([
    for svc_name, svc in var.services : {
      for p in svc.task_role_inline_policies :
      "${svc_name}-${p.name}" => merge(p, { svc_name = svc_name })
    } if svc.create_task_role
  ]...)

  scheduled_actions = merge([
    for svc_name, svc in var.services : {
      for action in svc.autoscaling.scheduled_actions :
      "${svc_name}-${action.name}" => merge(action, { svc_name = svc_name })
    } if svc.autoscaling.enabled
  ]...)

  step_scaling_policies = merge([
    for svc_name, svc in var.services : {
      for p in svc.autoscaling.step_scaling_policies :
      "${svc_name}-${p.name}" => merge(p, { svc_name = svc_name })
    } if svc.autoscaling.enabled
  ]...)
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

################################################################################
# CloudWatch Log Groups (per service/tier)
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_group_services

  name              = local.log_group_name[each.key]
  retention_in_days = each.value.cloudwatch_log_retention_days
  kms_key_id        = each.value.cloudwatch_log_kms_key_id
  tags              = local.default_tags
}

resource "aws_cloudwatch_log_group" "exec" {
  for_each = local.exec_log_services

  name              = "/ecs/${var.name}/${each.key}/exec"
  retention_in_days = each.value.cloudwatch_log_retention_days
  kms_key_id        = each.value.cloudwatch_log_kms_key_id
  tags              = local.default_tags
}

################################################################################
# ECS Cluster (shared by all tiers)
################################################################################

resource "aws_ecs_cluster" "this" {
  count = var.create_cluster ? 1 : 0

  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  # Enable execute_command at cluster level if any service uses it
  dynamic "configuration" {
    for_each = anytrue([for svc in var.services : svc.enable_execute_command]) ? [1] : []
    content {
      execute_command_configuration {
        logging    = var.execute_command_logging
        kms_key_id = var.execute_command_kms_key_id

        dynamic "log_configuration" {
          for_each = var.execute_command_logging == "OVERRIDE" ? [1] : []
          content {
            cloud_watch_log_group_name = (
              var.execute_command_log_group_name != ""
              ? var.execute_command_log_group_name
              : "/ecs/${local.cluster_name}/exec"
            )
          }
        }
      }
    }
  }

  tags = local.default_tags
}

################################################################################
# Cluster Capacity Providers
################################################################################

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = var.create_cluster ? 1 : 0

  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = var.capacity_providers

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}

################################################################################
# Service Connect Namespace (Cloud Map HTTP) — shared by all tiers
################################################################################

resource "aws_service_discovery_http_namespace" "this" {
  count = var.enable_service_connect_namespace ? 1 : 0

  name        = var.service_connect_namespace_name != "" ? var.service_connect_namespace_name : local.cluster_name
  description = "Service Connect namespace for ECS cluster ${local.cluster_name}"
  tags        = local.default_tags
}

################################################################################
# IAM — Shared ECS task assume-role policy document
################################################################################

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    # Prevent confused deputy
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

################################################################################
# IAM — Task Execution Role (per service/tier)
################################################################################

resource "aws_iam_role" "task_execution" {
  for_each = local.task_exec_role_services

  name               = "${var.name}-${each.key}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.default_tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  for_each = local.task_exec_role_services

  role       = aws_iam_role.task_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets access policy (only for services with secrets_arns)
data "aws_iam_policy_document" "task_execution_secrets" {
  for_each = local.task_exec_secrets_services

  statement {
    sid    = "GetSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameters",
      "ssm:GetParameter",
    ]
    resources = each.value.secrets_arns
  }

  dynamic "statement" {
    for_each = var.execute_command_kms_key_id != null ? [1] : []
    content {
      sid       = "KMSDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.execute_command_kms_key_id]
    }
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  for_each = local.task_exec_secrets_services

  name   = "${var.name}-${each.key}-task-exec-secrets"
  role   = aws_iam_role.task_execution[each.key].id
  policy = data.aws_iam_policy_document.task_execution_secrets[each.key].json
}

# ECR pull policy (only for services with ecr_repository_arns)
data "aws_iam_policy_document" "task_execution_ecr" {
  for_each = local.task_exec_ecr_services

  statement {
    sid    = "ECRPull"
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = each.value.ecr_repository_arns
  }

  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_execution_ecr" {
  for_each = local.task_exec_ecr_services

  name   = "${var.name}-${each.key}-task-exec-ecr"
  role   = aws_iam_role.task_execution[each.key].id
  policy = data.aws_iam_policy_document.task_execution_ecr[each.key].json
}

# Additional managed policies for task execution role
resource "aws_iam_role_policy_attachment" "task_execution_additional" {
  for_each = local.task_exec_additional

  role       = aws_iam_role.task_execution[each.value.svc_name].name
  policy_arn = each.value.policy_arn
}

# Inline policies for task execution role
resource "aws_iam_role_policy" "task_execution_inline" {
  for_each = local.task_exec_inline

  name   = each.key
  role   = aws_iam_role.task_execution[each.value.svc_name].id
  policy = each.value.policy
}

################################################################################
# IAM — Task Role / Application Permissions (per service/tier)
################################################################################

resource "aws_iam_role" "task" {
  for_each = local.task_role_services

  name               = "${var.name}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.default_tags
}

# ECS Exec permissions on the task role
data "aws_iam_policy_document" "ecs_exec" {
  for_each = local.task_exec_cmd_services

  statement {
    sid    = "ECSExec"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.execute_command_kms_key_id != null ? [1] : []
    content {
      sid       = "ECSExecKMS"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.execute_command_kms_key_id]
    }
  }

  statement {
    sid    = "ECSExecLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_exec" {
  for_each = local.task_exec_cmd_services

  name   = "${var.name}-${each.key}-ecs-exec"
  role   = aws_iam_role.task[each.key].id
  policy = data.aws_iam_policy_document.ecs_exec[each.key].json
}

# Additional managed policies for task role
resource "aws_iam_role_policy_attachment" "task_additional" {
  for_each = local.task_additional

  role       = aws_iam_role.task[each.value.svc_name].name
  policy_arn = each.value.policy_arn
}

# Inline policies for task role
resource "aws_iam_role_policy" "task_inline" {
  for_each = local.task_inline

  name   = each.key
  role   = aws_iam_role.task[each.value.svc_name].id
  policy = each.value.policy
}

################################################################################
# Security Group (one per service/tier — enforces tier isolation)
################################################################################

resource "aws_security_group" "this" {
  for_each = local.sg_services

  name_prefix = "${var.name}-${each.key}-ecs-"
  description = "Security group for ECS Fargate tier: ${var.name}-${each.key}"
  vpc_id      = each.value.vpc_id

  tags = merge(local.default_tags, {
    Name = "${var.name}-${each.key}-ecs-sg"
    Tier = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ingress" {
  for_each = local.sg_ingress_rules

  type                     = "ingress"
  security_group_id        = aws_security_group.this[each.value.svc_name].id
  description              = each.value.description
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  ipv6_cidr_blocks         = length(each.value.ipv6_cidr_blocks) > 0 ? each.value.ipv6_cidr_blocks : null
  source_security_group_id = each.value.source_security_group_id
  self                     = each.value.self ? true : null
}

resource "aws_security_group_rule" "egress" {
  for_each = local.sg_egress_rules

  type                     = "egress"
  security_group_id        = aws_security_group.this[each.value.svc_name].id
  description              = each.value.description
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  ipv6_cidr_blocks         = length(each.value.ipv6_cidr_blocks) > 0 ? each.value.ipv6_cidr_blocks : null
  source_security_group_id = each.value.destination_security_group_id
}

################################################################################
# Task Definition (per service/tier)
################################################################################

resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.task_cpu
  memory                   = each.value.task_memory
  container_definitions    = local.container_definitions_json[each.key]
  pid_mode                 = each.value.task_pid_mode

  execution_role_arn = lookup(
    { for k, v in aws_iam_role.task_execution : k => v.arn },
    each.key,
    each.value.task_execution_role_arn
  )
  task_role_arn = lookup(
    { for k, v in aws_iam_role.task : k => v.arn },
    each.key,
    each.value.task_role_arn
  )

  runtime_platform {
    operating_system_family = each.value.runtime_platform.operating_system_family
    cpu_architecture        = each.value.runtime_platform.cpu_architecture
  }

  dynamic "ephemeral_storage" {
    for_each = each.value.task_ephemeral_storage_gib != null ? [1] : []
    content {
      size_in_gib = each.value.task_ephemeral_storage_gib
    }
  }

  # EFS Volumes
  dynamic "volume" {
    for_each = each.value.efs_volumes
    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = volume.value.root_directory
        transit_encryption      = volume.value.transit_encryption
        transit_encryption_port = volume.value.transit_encryption_port

        dynamic "authorization_config" {
          for_each = volume.value.authorization_config != null ? [volume.value.authorization_config] : []
          content {
            access_point_id = authorization_config.value.access_point_id
            iam             = authorization_config.value.iam
          }
        }
      }
    }
  }

  # Bind Mount Volumes
  dynamic "volume" {
    for_each = each.value.bind_mount_volumes
    content {
      name = volume.value.name
    }
  }

  # Docker Volumes
  dynamic "volume" {
    for_each = each.value.docker_volumes
    content {
      name = volume.value.name

      docker_volume_configuration {
        scope         = volume.value.scope
        autoprovision = volume.value.autoprovision
        driver        = volume.value.driver
        driver_opts   = volume.value.driver_opts
        labels        = volume.value.labels
      }
    }
  }

  tags = local.default_tags
}

################################################################################
# ECS Service (per tier)
#
# All 4 ECS-native deployment strategies are supported per tier:
#   ROLLING | BLUE_GREEN | LINEAR | CANARY
################################################################################

resource "aws_ecs_service" "this" {
  for_each = var.services

  name            = "${var.name}-${each.key}"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count

  # Fargate launch settings
  launch_type      = length(var.default_capacity_provider_strategy) == 0 ? "FARGATE" : null
  platform_version = each.value.platform_version

  # Capacity provider strategy (overrides launch_type when set)
  dynamic "capacity_provider_strategy" {
    for_each = length(var.default_capacity_provider_strategy) > 0 ? var.default_capacity_provider_strategy : []
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  # Rolling deployment thresholds (top-level in provider 6.x)
  deployment_maximum_percent         = each.value.deployment_maximum_percent
  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent

  # Circuit breaker (top-level in provider 6.x)
  deployment_circuit_breaker {
    enable   = each.value.deployment_circuit_breaker.enable
    rollback = each.value.deployment_circuit_breaker.rollback
  }

  # ============================================================================
  # Deployment Configuration — strategy-specific settings (provider >= 6.4.0)
  # ROLLING | BLUE_GREEN | LINEAR | CANARY
  # ============================================================================
  deployment_configuration {
    strategy             = each.value.deployment_strategy
    bake_time_in_minutes = each.value.deployment_strategy != "ROLLING" ? each.value.bake_time_in_minutes : null

    dynamic "alarms" {
      for_each = each.value.deployment_alarms.enable && length(each.value.deployment_alarms.alarm_names) > 0 ? [1] : []
      content {
        alarm_names = each.value.deployment_alarms.alarm_names
        enable      = each.value.deployment_alarms.enable
        rollback    = each.value.deployment_alarms.rollback
      }
    }

    dynamic "linear_configuration" {
      for_each = each.value.deployment_strategy == "LINEAR" ? [each.value.linear_config] : []
      content {
        step_percent              = linear_configuration.value.step_percent
        step_bake_time_in_minutes = linear_configuration.value.step_bake_time_in_minutes
      }
    }

    dynamic "canary_configuration" {
      for_each = each.value.deployment_strategy == "CANARY" ? [each.value.canary_config] : []
      content {
        canary_percent              = canary_configuration.value.canary_percent
        canary_bake_time_in_minutes = canary_configuration.value.canary_bake_time_in_minutes
      }
    }

    dynamic "lifecycle_hook" {
      for_each = each.value.deployment_strategy != "ROLLING" ? each.value.lifecycle_hooks : []
      content {
        hook_target_arn  = lifecycle_hook.value.hook_target_arn
        role_arn         = lifecycle_hook.value.role_arn
        lifecycle_stages = lifecycle_hook.value.lifecycle_stages
        hook_details     = lifecycle_hook.value.hook_details
      }
    }
  }

  # Networking
  network_configuration {
    subnets = each.value.subnet_ids
    security_groups = concat(
      each.value.security_group_ids,
      each.value.create_security_group ? [aws_security_group.this[each.key].id] : []
    )
    assign_public_ip = each.value.assign_public_ip
  }

  # ============================================================================
  # Load Balancer — with advanced_configuration for B/G/Linear/Canary
  # ============================================================================
  dynamic "load_balancer" {
    for_each = each.value.load_balancer_config
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port

      dynamic "advanced_configuration" {
        for_each = each.value.deployment_strategy != "ROLLING" && (
          each.value.create_green_target_group || each.value.blue_green_config.alternate_target_group_arn != ""
        ) ? [1] : []
        content {
          alternate_target_group_arn = lookup(
            { for k, v in aws_lb_target_group.green : k => v.arn },
            each.key,
            each.value.blue_green_config.alternate_target_group_arn
          )
          production_listener_rule = each.value.blue_green_config.production_listener_rule
          role_arn = lookup(
            { for k, v in aws_iam_role.ecs_alb_service : k => v.arn },
            each.key,
            each.value.ecs_alb_service_role_arn
          )
        }
      }
    }
  }

  # Service Connect (tier-to-tier mesh)
  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect_configuration.enabled ? [each.value.service_connect_configuration] : []
    content {
      enabled   = true
      namespace = service_connect_configuration.value.namespace

      dynamic "log_configuration" {
        for_each = service_connect_configuration.value.log_configuration != null ? [service_connect_configuration.value.log_configuration] : []
        content {
          log_driver = log_configuration.value.log_driver
          options    = log_configuration.value.options

          dynamic "secret_option" {
            for_each = log_configuration.value.secret_option
            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      dynamic "service" {
        for_each = service_connect_configuration.value.services
        content {
          port_name             = service.value.port_name
          discovery_name        = service.value.discovery_name
          ingress_port_override = service.value.ingress_port_override

          dynamic "timeout" {
            for_each = service.value.timeout != null ? [service.value.timeout] : []
            content {
              idle_timeout_seconds        = timeout.value.idle_timeout_seconds
              per_request_timeout_seconds = timeout.value.per_request_timeout_seconds
            }
          }

          dynamic "tls" {
            for_each = service.value.tls != null ? [service.value.tls] : []
            content {
              issuer_cert_authority {
                aws_pca_authority_arn = tls.value.issuer_cert_authority.aws_pca_authority_arn
              }
              kms_key  = tls.value.kms_key
              role_arn = tls.value.role_arn
            }
          }

          dynamic "client_alias" {
            for_each = service.value.client_alias
            content {
              dns_name = client_alias.value.dns_name
              port     = client_alias.value.port
            }
          }
        }
      }
    }
  }

  # Service Registries (Cloud Map DNS)
  dynamic "service_registries" {
    for_each = each.value.service_registries
    content {
      registry_arn   = service_registries.value.registry_arn
      port           = service_registries.value.port
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
    }
  }

  enable_execute_command  = each.value.enable_execute_command
  enable_ecs_managed_tags = each.value.enable_ecs_managed_tags
  propagate_tags          = each.value.propagate_tags

  health_check_grace_period_seconds = length(each.value.load_balancer_config) > 0 ? each.value.health_check_grace_period_seconds : null

  dynamic "ordered_placement_strategy" {
    for_each = each.value.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  dynamic "placement_constraints" {
    for_each = each.value.placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression
    }
  }

  scheduling_strategy   = each.value.scheduling_strategy
  force_new_deployment  = each.value.force_new_deployment
  wait_for_steady_state = each.value.wait_for_steady_state

  tags = local.default_tags

  # Ignore desired_count (autoscaling manages it) and task_definition
  # (ECS updates task_definition during B/G deployments)
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  depends_on = [
    aws_iam_role_policy_attachment.task_execution_managed,
    aws_iam_role_policy.task_execution_secrets,
    aws_iam_role_policy.task_execution_ecr,
  ]
}

################################################################################
# Green Target Group (per service, for B/G, Linear, Canary)
################################################################################

resource "aws_lb_target_group" "green" {
  for_each = local.green_tg_services

  name                 = each.value.green_target_group.name != "" ? each.value.green_target_group.name : "${var.name}-${each.key}-green"
  port                 = each.value.green_target_group.port
  protocol             = each.value.green_target_group.protocol
  vpc_id               = each.value.vpc_id
  target_type          = "ip"
  deregistration_delay = each.value.green_target_group.deregistration_delay

  health_check {
    path                = each.value.green_target_group.health_check.path
    port                = each.value.green_target_group.health_check.port
    healthy_threshold   = each.value.green_target_group.health_check.healthy_threshold
    unhealthy_threshold = each.value.green_target_group.health_check.unhealthy_threshold
    timeout             = each.value.green_target_group.health_check.timeout
    interval            = each.value.green_target_group.health_check.interval
    matcher             = each.value.green_target_group.health_check.matcher
  }

  tags = merge(local.default_tags, {
    Name      = "${var.name}-${each.key}-green"
    BlueGreen = "green"
    Tier      = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# ECS ALB Service Role (per service — required for B/G traffic shifting)
#
# ECS needs this role to manage ALB listener rule weights during
# Blue/Green, Linear, and Canary deployments.
################################################################################

data "aws_iam_policy_document" "ecs_alb_assume_role" {
  for_each = local.ecs_alb_services

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_alb_service" {
  for_each = local.ecs_alb_services

  name               = "${var.name}-${each.key}-ecs-alb-service-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_alb_assume_role[each.key].json
  tags               = local.default_tags
}

resource "aws_iam_role_policy_attachment" "ecs_alb_service" {
  for_each = local.ecs_alb_services

  role       = aws_iam_role.ecs_alb_service[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

################################################################################
# Auto Scaling (per service/tier)
################################################################################

resource "aws_appautoscaling_target" "this" {
  for_each = local.autoscaling_services

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.create_cluster ? aws_ecs_cluster.this[0].name : split("/", var.cluster_arn)[1]}/${aws_ecs_service.this[each.key].name}"
  min_capacity       = each.value.autoscaling.min_capacity
  max_capacity       = each.value.autoscaling.max_capacity

  tags = local.default_tags
}

# CPU Target Tracking Policy
resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.cpu_autoscaling_services

  name               = "${var.name}-${each.key}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.autoscaling.cpu_target.target_value
    scale_in_cooldown  = each.value.autoscaling.cpu_target.scale_in_cooldown
    scale_out_cooldown = each.value.autoscaling.cpu_target.scale_out_cooldown
    disable_scale_in   = each.value.autoscaling.cpu_target.disable_scale_in

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# Memory Target Tracking Policy
resource "aws_appautoscaling_policy" "memory" {
  for_each = local.memory_autoscaling_services

  name               = "${var.name}-${each.key}-memory-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.autoscaling.memory_target.target_value
    scale_in_cooldown  = each.value.autoscaling.memory_target.scale_in_cooldown
    scale_out_cooldown = each.value.autoscaling.memory_target.scale_out_cooldown
    disable_scale_in   = each.value.autoscaling.memory_target.disable_scale_in

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# ALB Request Count Target Tracking Policy
resource "aws_appautoscaling_policy" "alb_requests" {
  for_each = local.alb_autoscaling_services

  name               = "${var.name}-${each.key}-alb-request-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.autoscaling.alb_request_count_target.target_value
    scale_in_cooldown  = each.value.autoscaling.alb_request_count_target.scale_in_cooldown
    scale_out_cooldown = each.value.autoscaling.alb_request_count_target.scale_out_cooldown
    disable_scale_in   = each.value.autoscaling.alb_request_count_target.disable_scale_in

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${each.value.autoscaling.alb_request_count_target.alb_arn_suffix}/${each.value.autoscaling.alb_request_count_target.target_group_arn_suffix}"
    }
  }
}

# Scheduled Scaling Actions
resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = local.scheduled_actions

  name               = each.key
  service_namespace  = aws_appautoscaling_target.this[each.value.svc_name].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.value.svc_name].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.value.svc_name].resource_id
  schedule           = each.value.schedule
  timezone           = each.value.timezone
  start_time         = each.value.start_time
  end_time           = each.value.end_time

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}

# Step Scaling Policies
resource "aws_appautoscaling_policy" "step" {
  for_each = local.step_scaling_policies

  name               = each.key
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.this[each.value.svc_name].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.value.svc_name].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.value.svc_name].resource_id

  step_scaling_policy_configuration {
    adjustment_type          = each.value.adjustment_type
    metric_aggregation_type  = each.value.metric_aggregation_type
    min_adjustment_magnitude = each.value.min_adjustment_magnitude
    cooldown                 = each.value.cooldown

    dynamic "step_adjustment" {
      for_each = each.value.step_adjustments
      content {
        scaling_adjustment          = step_adjustment.value.scaling_adjustment
        metric_interval_lower_bound = step_adjustment.value.metric_interval_lower_bound
        metric_interval_upper_bound = step_adjustment.value.metric_interval_upper_bound
      }
    }
  }
}

################################################################################
# CloudWatch Alarms (per service/tier)
################################################################################

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.alarm_services

  alarm_name          = "${var.name}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.alarm_cpu_threshold
  alarm_description   = "ECS CPU utilization >= ${each.value.alarm_cpu_threshold}% for ${var.name}-${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.create_cluster ? aws_ecs_cluster.this[0].name : split("/", var.cluster_arn)[1]
    ServiceName = aws_ecs_service.this[each.key].name
  }

  alarm_actions = each.value.alarm_sns_topic_arns
  ok_actions    = each.value.alarm_sns_topic_arns
  tags          = local.default_tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = local.alarm_services

  alarm_name          = "${var.name}-${each.key}-memory-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.alarm_memory_threshold
  alarm_description   = "ECS Memory utilization >= ${each.value.alarm_memory_threshold}% for ${var.name}-${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.create_cluster ? aws_ecs_cluster.this[0].name : split("/", var.cluster_arn)[1]
    ServiceName = aws_ecs_service.this[each.key].name
  }

  alarm_actions = each.value.alarm_sns_topic_arns
  ok_actions    = each.value.alarm_sns_topic_arns
  tags          = local.default_tags
}

resource "aws_cloudwatch_metric_alarm" "running_task_count" {
  for_each = local.alarm_services

  alarm_name          = "${var.name}-${each.key}-low-task-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = each.value.alarm_running_task_count_threshold
  alarm_description   = "Running task count < ${each.value.alarm_running_task_count_threshold} for ${var.name}-${each.key}"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = var.create_cluster ? aws_ecs_cluster.this[0].name : split("/", var.cluster_arn)[1]
    ServiceName = aws_ecs_service.this[each.key].name
  }

  alarm_actions = each.value.alarm_sns_topic_arns
  ok_actions    = each.value.alarm_sns_topic_arns
  tags          = local.default_tags
}

################################################################################
# Service Discovery — Cloud Map DNS (per service/tier)
################################################################################

resource "aws_service_discovery_service" "this" {
  for_each = local.sd_services

  name = "${var.name}-${each.key}"

  dynamic "dns_config" {
    for_each = each.value.service_discovery.dns_config != null ? [each.value.service_discovery.dns_config] : []
    content {
      namespace_id   = dns_config.value.namespace_id != null ? dns_config.value.namespace_id : each.value.service_discovery.namespace_id
      routing_policy = dns_config.value.routing_policy

      dynamic "dns_records" {
        for_each = dns_config.value.dns_records
        content {
          type = dns_records.value.type
          ttl  = dns_records.value.ttl
        }
      }
    }
  }

  dynamic "health_check_custom_config" {
    for_each = each.value.service_discovery.health_check_custom_config != null ? [each.value.service_discovery.health_check_custom_config] : []
    content {
      failure_threshold = health_check_custom_config.value.failure_threshold
    }
  }

  tags = local.default_tags
}
