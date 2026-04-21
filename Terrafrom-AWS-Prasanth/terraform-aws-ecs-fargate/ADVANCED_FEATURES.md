# Advanced Features Reference

This document focuses on the parts of the module that go beyond a plain
single-service ECS deployment.

## What This File Covers

- cluster-level advanced configuration
- task definition synthesis details
- Service Connect and Service Connect TLS
- ECS-native traffic shifting strategies
- autoscaling and observability features
- legacy controller support that still exists in the codebase

## Cluster-Level Features

## Managed Storage Configuration

The module passes `cluster_configuration` directly to the ECS cluster and
supports nested `managed_storage_configuration`.

Typical use:

```hcl
cluster_configuration = [
  {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = var.exec_log_group_name
      }
    }

    managed_storage_configuration = {
      fargate_ephemeral_storage_kms_key_id = var.fargate_ephemeral_storage_kms_key_id
      kms_key_id                           = var.managed_storage_kms_key_id
    }
  }
]
```

Use this when:

- ECS Exec logs need explicit log routing
- Fargate ephemeral storage encryption must use customer-managed KMS keys

## Cluster Default Capacity Providers

The cluster can expose both `FARGATE` and `FARGATE_SPOT` and define a default
strategy:

```hcl
capacity_providers = ["FARGATE", "FARGATE_SPOT"]

default_capacity_provider_strategy = [
  {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
]
```

Service-level `capacity_provider_strategy` overrides that default.

## Task Definition Synthesis

For most services, the module synthesizes `container_definitions` from common
task fields.

Supported synthesized inputs include:

- `image`
- `cpu`
- `memory`
- `memoryReservation`
- `environment`
- `secrets`
- `command`
- `entrypoint`
- `port_mappings`
- `mount_points`
- `volumes_from`
- `firelens_configuration`
- `health_check`
- `ephemeral_storage`
- `operating_system_family`
- `cpu_architecture`

When you need exact JSON control, use:

- `task_definition.container_definition`

That bypasses the synthesized path and lets you provide the full container
definition JSON yourself.

## Service Connect

Service Connect can be configured both at cluster default level and per
service.

Cluster default example:

```hcl
service_connect_configuration = {
  enabled   = true
  namespace = var.service_connect_namespace_arn
}
```

Per-service example:

```hcl
service = {
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
```

Important requirement:

- `service_connect.services[].port_name` must match the `name` of a container
  port mapping

## Service Connect TLS

The service-level Service Connect block supports TLS:

```hcl
service_connect = {
  enabled   = true
  namespace = var.service_connect_namespace_arn

  services = [
    {
      port_name = "api-http"
      tls = {
        issuer_cert_authority = {
          aws_pca_authority_arn = var.aws_pca_authority_arn
        }
        kms_key  = var.service_connect_tls_kms_key_arn
        role_arn = var.service_connect_tls_role_arn
      }
    }
  ]
}
```

This requires the surrounding PCA, IAM, and KMS resources to exist already.

## ECS-Native Deployment Strategies

The maintained path in this repository is ECS-native deployment management
through `aws_ecs_service.deployment_configuration`.

Supported strategies:

- `ROLLING`
- `BLUE_GREEN`
- `LINEAR`
- `CANARY`

Set them at:

- module level with `deployment_strategy_default`
- service level with `service.deployment_configuration.strategy`

## Rolling

Use for:

- standard service rollouts
- workers
- services without advanced listener-rule traffic shifting

## Blue/Green, Linear, and Canary

These strategies require advanced load balancer inputs on the service target
group mapping:

- `target_group_arn`
- `alternate_target_group_arn`
- `production_listener_rule`

They also require:

- `service.deployment_configuration.ecs_alb_service_role_arn`

Example:

```hcl
service = {
  deployment_configuration = {
    strategy                 = "CANARY"
    bake_time_in_minutes     = 10
    ecs_alb_service_role_arn = var.api_ecs_alb_service_role_arn

    canary_configuration = {
      canary_percent              = 10
      canary_bake_time_in_minutes = 10
    }
  }

  target_groups = [
    {
      target_group_arn           = var.api_blue_target_group_arn
      alternate_target_group_arn = var.api_green_target_group_arn
      production_listener_rule   = var.api_production_listener_rule_arn
      container_name             = "api"
      container_port             = 8080
    }
  ]
}
```

## Deployment Alarms And Lifecycle Hooks

The module supports:

- deployment alarms
- circuit breaker
- lifecycle hooks for non-rolling strategies

Example:

```hcl
service = {
  deployment_configuration = {
    strategy = "LINEAR"

    alarms = {
      enable      = true
      rollback    = true
      alarm_names = var.api_deployment_alarm_names
    }

    lifecycle_hooks = [
      {
        hook_target_arn  = var.validation_lambda_arn
        role_arn         = var.validation_hook_role_arn
        lifecycle_stages = ["TEST_TRAFFIC_SHIFT"]
      }
    ]
  }
}
```

## Autoscaling

The module supports per-service autoscaling for:

- CPU target tracking
- memory target tracking
- ALB request count target tracking
- scheduled scaling
- step scaling

Typical service block:

```hcl
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
```

Use ALB request count only for services that are actually target-group attached.

## Observability And Operations

Useful service flags:

- `enable_execute_command`
- `enable_ecs_managed_tags`
- `health_check_grace_period_seconds`
- `wait_for_steady_state`

These are exposed directly in the maintained examples.

## Legacy Controller Support

The codebase still contains support for:

- `deployment_controller.type = "CODE_DEPLOY"`
- `deployment_controller.type = "EXTERNAL"`

Those paths remain for backward compatibility, but they are not the primary
recommended path for this repository. The maintained examples and the main user
guide focus on ECS-native deployments because they are the cleanest Fargate
path with the current AWS provider.

## Current Boundaries

Advanced does not mean fully self-contained. The module still expects external
ownership of:

- IAM roles
- target groups
- listener rules
- namespaces
- security groups
- log groups

That separation is intentional and keeps the module focused on ECS Fargate
resources rather than entire platform bootstrapping.
