################################################################################
# General (Cluster-level)
################################################################################

variable "name" {
  description = "Name prefix for all resources created by this module"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 255
    error_message = "Name must be between 1 and 255 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "uat", "prod", "sandbox"], var.environment)
    error_message = "Environment must be one of: dev, staging, uat, prod, sandbox."
  }
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# ECS Cluster
################################################################################

variable "create_cluster" {
  description = "Whether to create a new ECS cluster or use an existing one"
  type        = bool
  default     = true
}

variable "cluster_arn" {
  description = "ARN of an existing ECS cluster (required if create_cluster = false)"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name for the ECS cluster (defaults to var.name)"
  type        = string
  default     = ""
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "execute_command_logging" {
  description = "ECS Exec logging configuration for the cluster: NONE, DEFAULT, OVERRIDE"
  type        = string
  default     = "OVERRIDE"

  validation {
    condition     = contains(["NONE", "DEFAULT", "OVERRIDE"], var.execute_command_logging)
    error_message = "execute_command_logging must be NONE, DEFAULT, or OVERRIDE."
  }
}

variable "execute_command_log_group_name" {
  description = "CloudWatch log group name for cluster-wide ECS Exec logs"
  type        = string
  default     = ""
}

variable "execute_command_kms_key_id" {
  description = "KMS key ID for encrypting ECS Exec data channel (cluster-wide)"
  type        = string
  default     = null
}

################################################################################
# Capacity Providers
################################################################################

variable "capacity_providers" {
  description = "List of Fargate capacity providers: FARGATE, FARGATE_SPOT"
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]

  validation {
    condition     = alltrue([for cp in var.capacity_providers : contains(["FARGATE", "FARGATE_SPOT"], cp)])
    error_message = "Capacity providers must be FARGATE and/or FARGATE_SPOT."
  }
}

variable "default_capacity_provider_strategy" {
  description = "Default capacity provider strategy for the cluster (applies to all services)"
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number, 0)
  }))
  default = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    }
  ]
}

################################################################################
# Service Connect (Cluster Namespace)
################################################################################

variable "enable_service_connect_namespace" {
  description = "Whether to create a Cloud Map HTTP namespace for Service Connect"
  type        = bool
  default     = false
}

variable "service_connect_namespace_name" {
  description = "Name for the Cloud Map HTTP namespace (defaults to cluster name)"
  type        = string
  default     = ""
}

################################################################################
# Multi-Tier Services
#
# Each key in the map represents an application tier (e.g. "frontend", "api",
# "worker"). The module creates a fully independent ECS service for every entry:
# its own task definition, IAM roles, security group, auto scaling policies,
# CloudWatch alarms, and deployment configuration — all on the shared cluster.
#
# Example:
#   services = {
#     frontend = { subnet_ids = [...], task_cpu = 256, container_definitions = [...] }
#     api      = { subnet_ids = [...], task_cpu = 512, container_definitions = [...] }
#     worker   = { subnet_ids = [...], task_cpu = 256, container_definitions = [...] }
#   }
################################################################################

variable "services" {
  description = <<-EOT
    Map of ECS services (application tiers) to deploy on the shared cluster.
    Key = tier/service name (e.g., "frontend", "api", "worker").
    Each entry is a self-contained service configuration with its own task
    definition, IAM roles, security group, auto scaling, and deployment strategy.
  EOT

  type = map(object({

    ##########################################################################
    # Task Definition
    ##########################################################################
    task_cpu    = optional(number, 256)
    task_memory = optional(number, 512)

    runtime_platform = optional(object({
      operating_system_family = optional(string, "LINUX")
      cpu_architecture        = optional(string, "X86_64")
    }), {})

    task_ephemeral_storage_gib = optional(number, null)
    task_pid_mode              = optional(string, null)

    # Required: list of ECS container definition objects
    container_definitions = any

    # Volumes
    efs_volumes = optional(list(object({
      name                    = string
      file_system_id          = string
      root_directory          = optional(string, "/")
      transit_encryption      = optional(string, "ENABLED")
      transit_encryption_port = optional(number, null)
      authorization_config = optional(object({
        access_point_id = optional(string, null)
        iam             = optional(string, "ENABLED")
      }), null)
    })), [])

    bind_mount_volumes = optional(list(object({
      name = string
    })), [])

    docker_volumes = optional(list(object({
      name          = string
      scope         = optional(string, "task")
      autoprovision = optional(bool, false)
      driver        = optional(string, "local")
      driver_opts   = optional(map(string), {})
      labels        = optional(map(string), {})
    })), [])

    ##########################################################################
    # ECS Service
    ##########################################################################
    desired_count                     = optional(number, 2)
    platform_version                  = optional(string, "LATEST")
    scheduling_strategy               = optional(string, "REPLICA")
    enable_execute_command            = optional(bool, true)
    force_new_deployment              = optional(bool, false)
    wait_for_steady_state             = optional(bool, true)
    enable_ecs_managed_tags           = optional(bool, true)
    propagate_tags                    = optional(string, "SERVICE")
    health_check_grace_period_seconds = optional(number, 60)

    ##########################################################################
    # Deployment Strategy
    # ROLLING (default) | BLUE_GREEN | LINEAR | CANARY
    ##########################################################################
    deployment_strategy                = optional(string, "ROLLING")
    deployment_maximum_percent         = optional(number, 200)
    deployment_minimum_healthy_percent = optional(number, 100)
    bake_time_in_minutes               = optional(number, 5)

    deployment_circuit_breaker = optional(object({
      enable   = bool
      rollback = bool
    }), { enable = true, rollback = true })

    deployment_alarms = optional(object({
      alarm_names = list(string)
      enable      = bool
      rollback    = bool
    }), { alarm_names = [], enable = false, rollback = true })

    blue_green_config = optional(object({
      alternate_target_group_arn = optional(string, "")
      production_listener_rule   = optional(string, "")
      role_arn                   = optional(string, "")
    }), {})

    linear_config = optional(object({
      step_percent              = optional(number, 25.0)
      step_bake_time_in_minutes = optional(number, 5)
    }), {})

    canary_config = optional(object({
      canary_percent              = optional(number, 10.0)
      canary_bake_time_in_minutes = optional(number, 10)
    }), {})

    lifecycle_hooks = optional(list(object({
      hook_target_arn  = string
      role_arn         = string
      lifecycle_stages = list(string)
      hook_details     = optional(string, null)
    })), [])

    ##########################################################################
    # Green Target Group (B/G, Linear, Canary)
    ##########################################################################
    create_green_target_group = optional(bool, false)
    green_target_group = optional(object({
      name                 = optional(string, "")
      port                 = optional(number, 8080)
      protocol             = optional(string, "HTTP")
      deregistration_delay = optional(number, 30)
      health_check = optional(object({
        path                = optional(string, "/health")
        port                = optional(string, "traffic-port")
        healthy_threshold   = optional(number, 2)
        unhealthy_threshold = optional(number, 3)
        timeout             = optional(number, 5)
        interval            = optional(number, 30)
        matcher             = optional(string, "200")
      }), {})
    }), {})

    ##########################################################################
    # ECS ALB Service Role (B/G traffic shifting)
    ##########################################################################
    create_ecs_alb_service_role = optional(bool, true)
    ecs_alb_service_role_arn    = optional(string, "")

    ##########################################################################
    # Networking
    ##########################################################################
    subnet_ids         = list(string)
    assign_public_ip   = optional(bool, false)
    vpc_id             = optional(string, "")
    security_group_ids = optional(list(string), [])

    create_security_group = optional(bool, true)

    security_group_ingress_rules = optional(list(object({
      description              = optional(string, "Ingress rule")
      from_port                = number
      to_port                  = number
      protocol                 = string
      cidr_blocks              = optional(list(string), [])
      ipv6_cidr_blocks         = optional(list(string), [])
      source_security_group_id = optional(string, null)
      self                     = optional(bool, false)
    })), [])

    security_group_egress_rules = optional(list(object({
      description                   = optional(string, "Egress rule")
      from_port                     = number
      to_port                       = number
      protocol                      = string
      cidr_blocks                   = optional(list(string), [])
      ipv6_cidr_blocks              = optional(list(string), [])
      destination_security_group_id = optional(string, null)
    })), [{
      description = "Allow all outbound"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }])

    ##########################################################################
    # Load Balancer
    ##########################################################################
    load_balancer_config = optional(list(object({
      target_group_arn = string
      container_name   = string
      container_port   = number
    })), [])

    ##########################################################################
    # Service Connect (tier-to-tier mesh communication)
    ##########################################################################
    service_connect_configuration = optional(object({
      enabled   = bool
      namespace = optional(string, null)
      log_configuration = optional(object({
        log_driver = string
        options    = optional(map(string), {})
        secret_option = optional(list(object({
          name       = string
          value_from = string
        })), [])
      }), null)
      services = optional(list(object({
        port_name             = string
        discovery_name        = optional(string, null)
        ingress_port_override = optional(number, null)
        timeout = optional(object({
          idle_timeout_seconds        = optional(number, null)
          per_request_timeout_seconds = optional(number, null)
        }), null)
        tls = optional(object({
          issuer_cert_authority = object({
            aws_pca_authority_arn = string
          })
          kms_key  = optional(string, null)
          role_arn = optional(string, null)
        }), null)
        client_alias = optional(list(object({
          dns_name = string
          port     = number
        })), [])
      })), [])
    }), { enabled = false })

    ##########################################################################
    # Service Discovery (Cloud Map DNS)
    ##########################################################################
    service_discovery = optional(object({
      enabled      = bool
      namespace_id = optional(string, null)
      dns_config = optional(object({
        namespace_id   = optional(string, null)
        routing_policy = optional(string, "MULTIVALUE")
        dns_records = optional(list(object({
          type = string
          ttl  = number
        })), [{ type = "A", ttl = 60 }])
      }), null)
      health_check_custom_config = optional(object({
        failure_threshold = optional(number, 1)
      }), null)
    }), { enabled = false })

    ##########################################################################
    # Service Registries (Cloud Map direct)
    ##########################################################################
    service_registries = optional(list(object({
      registry_arn   = string
      port           = optional(number, null)
      container_name = optional(string, null)
      container_port = optional(number, null)
    })), [])

    ##########################################################################
    # Placement
    ##########################################################################
    ordered_placement_strategy = optional(list(object({
      type  = string
      field = optional(string, null)
    })), [])

    placement_constraints = optional(list(object({
      type       = string
      expression = optional(string, null)
    })), [])

    ##########################################################################
    # IAM — Task Execution Role
    ##########################################################################
    create_task_execution_role              = optional(bool, true)
    task_execution_role_arn                 = optional(string, "")
    task_execution_role_additional_policies = optional(list(string), [])
    task_execution_role_inline_policies = optional(list(object({
      name   = string
      policy = string
    })), [])
    secrets_arns        = optional(list(string), [])
    ecr_repository_arns = optional(list(string), [])

    ##########################################################################
    # IAM — Task Role (application permissions)
    ##########################################################################
    create_task_role              = optional(bool, true)
    task_role_arn                 = optional(string, "")
    task_role_additional_policies = optional(list(string), [])
    task_role_inline_policies = optional(list(object({
      name   = string
      policy = string
    })), [])

    ##########################################################################
    # CloudWatch Logging
    ##########################################################################
    create_cloudwatch_log_group   = optional(bool, true)
    cloudwatch_log_group_name     = optional(string, "")
    cloudwatch_log_retention_days = optional(number, 30)
    cloudwatch_log_kms_key_id     = optional(string, null)

    ##########################################################################
    # CloudWatch Alarms
    ##########################################################################
    enable_cloudwatch_alarms           = optional(bool, true)
    alarm_sns_topic_arns               = optional(list(string), [])
    alarm_cpu_threshold                = optional(number, 80)
    alarm_memory_threshold             = optional(number, 80)
    alarm_running_task_count_threshold = optional(number, 1)

    ##########################################################################
    # Auto Scaling
    ##########################################################################
    autoscaling = optional(object({
      enabled      = bool
      min_capacity = optional(number, 1)
      max_capacity = optional(number, 10)

      cpu_target = optional(object({
        target_value       = number
        scale_in_cooldown  = optional(number, 300)
        scale_out_cooldown = optional(number, 60)
        disable_scale_in   = optional(bool, false)
      }), null)

      memory_target = optional(object({
        target_value       = number
        scale_in_cooldown  = optional(number, 300)
        scale_out_cooldown = optional(number, 60)
        disable_scale_in   = optional(bool, false)
      }), null)

      alb_request_count_target = optional(object({
        target_value            = number
        alb_arn_suffix          = string
        target_group_arn_suffix = string
        scale_in_cooldown       = optional(number, 300)
        scale_out_cooldown      = optional(number, 60)
        disable_scale_in        = optional(bool, false)
      }), null)

      scheduled_actions = optional(list(object({
        name         = string
        schedule     = string
        timezone     = optional(string, "UTC")
        min_capacity = optional(number, null)
        max_capacity = optional(number, null)
        start_time   = optional(string, null)
        end_time     = optional(string, null)
      })), [])

      step_scaling_policies = optional(list(object({
        name                     = string
        adjustment_type          = string
        metric_aggregation_type  = optional(string, "Average")
        min_adjustment_magnitude = optional(number, null)
        cooldown                 = optional(number, 60)
        step_adjustments = list(object({
          scaling_adjustment          = number
          metric_interval_lower_bound = optional(number, null)
          metric_interval_upper_bound = optional(number, null)
        }))
      })), [])
    }), { enabled = false })
  }))

  validation {
    condition     = length(var.services) > 0
    error_message = "At least one service/tier must be defined in var.services."
  }
}
