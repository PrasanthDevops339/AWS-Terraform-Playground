# terraform-aws-ecs-fargate

Fargate-only Terraform module for creating one ECS cluster and one or more ECS
services from a single `container_config` map.

## Scope

This module is intentionally opinionated:

- Fargate only
- one shared ECS cluster
- one or more ECS services and task definitions
- external network, IAM, log groups, and load balancer resources

It supports multi-tier applications by treating each key in `container_config`
as an independent service boundary. A typical shape is `frontend`, `api`, and
`worker` on the same cluster.

This module is not a drop-in mirror of
`terraform-aws-modules/terraform-aws-ecs`. It covers the ECS Fargate features
used by this repository and keeps the surrounding infrastructure explicit
instead of auto-creating everything inside the module.

## Version Requirements

- Terraform `>= 1.5.7`
- AWS provider `>= 6.34.0`

The module uses newer AWS provider arguments for ECS-native deployment
strategies and newer Terraform type features. Terraform `1.1.x` is too old for
the current inputs.

## What The Module Manages

- ECS cluster
- ECS cluster settings and optional managed storage configuration
- cluster default capacity provider strategy
- ECS task definitions
- ECS services
- ECS-native deployment strategies: `ROLLING`, `BLUE_GREEN`, `LINEAR`,
  `CANARY`
- service-level load balancer attachment to external target groups
- Service Connect, including optional TLS blocks
- Cloud Map service registries
- autoscaling policies and scheduled actions
- per-service CloudWatch alarms
- ECS Exec enablement
- EFS task volumes

## What You Provide Externally

This module expects these resources to exist already and be passed in:

- VPC and subnet IDs
- security group IDs
- task execution role ARNs
- task role ARNs
- CloudWatch log groups
- target groups and listener rules
- ECS ALB infrastructure role ARN for ECS-native traffic shifting
- Cloud Map namespace ARN if Service Connect is enabled
- optional PCA and KMS resources for Service Connect TLS

## Multi-Tier Model

Each `container_config` entry becomes:

- one task definition
- one ECS service
- optional autoscaling resources
- optional deployment alarms

That is enough to model:

- `frontend`: public, target-group attached, usually `ROLLING`
- `api`: internal or mixed, often `CANARY` or `LINEAR`
- `worker`: private, usually no load balancer, often `FARGATE_SPOT` weighted

## Quick Start

```hcl
module "ecs_service" {
  source = "./terraform-aws-ecs-fargate"

  cluster_name = "my-app"
  vpc_id       = var.vpc_id

  container_config = {
    app = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = var.log_group_name

        port_mappings = [
          {
            name          = "http"
            containerPort = 8080
            hostPort      = 8080
            protocol      = "tcp"
            appProtocol   = "http"
          }
        ]
      }

      service = {
        desired_count                     = 2
        security_groups                   = [var.service_security_group_id]
        subnets                           = var.private_subnet_ids
        enable_execute_command            = true
        enable_ecs_managed_tags           = true
        health_check_grace_period_seconds = 60

        target_groups = [
          {
            target_group_arn = var.target_group_arn
            container_name   = "app"
            container_port   = 8080
          }
        ]
      }
    }
  }
}
```

## Container Definition Paths

For most services, use the synthesized task definition fields:

- `task_definition.image`
- `task_definition.environment`
- `task_definition.port_mappings`
- `task_definition.mount_points`
- `task_definition.firelens_configuration`
- `task_definition.ephemeral_storage`
- `task_definition.operating_system_family`
- `task_definition.cpu_architecture`

If you need complete control, pass a prebuilt JSON string through:

- `task_definition.container_definition`

Service Connect requires a named port mapping. The value of
`service.service_connect.services[].port_name` must match the `name` of one of
the container `port_mappings`.

## Deployment Strategy Notes

The maintained examples focus on ECS-native service deployments, not
CodeDeploy-first workflows.

- `ROLLING` works with a normal target group or with no target group at all
- `BLUE_GREEN`, `LINEAR`, and `CANARY` require advanced LB wiring
- non-rolling traffic shifting requires
  `target_groups[].alternate_target_group_arn`
- non-rolling traffic shifting requires
  `target_groups[].production_listener_rule`
- non-rolling traffic shifting requires
  `service.deployment_configuration.ecs_alb_service_role_arn`

The module still contains legacy `CODE_DEPLOY` and `EXTERNAL` controller paths,
but the maintained examples and primary documentation are centered on ECS-native
Fargate deployments.

## Current Gaps

- no service `volume_configuration` support for ECS-managed EBS volumes
- no VPC Lattice integration
- no Service Connect test traffic rule surface
- no integrated creation of IAM roles, security groups, target groups, or log
  groups

## Documentation Map

- [`USER_GUIDE.md`](./USER_GUIDE.md): usage guide for multi-tier patterns and
  deployment strategies
- [`ADVANCED_FEATURES.md`](./ADVANCED_FEATURES.md): focused reference for
  Service Connect, traffic shifting, autoscaling, and task definition options
- [`examples/simple`](./examples/simple): minimal single-service consumer
- [`examples/complete`](./examples/complete): three-tier example with Service
  Connect, canary deployment, and autoscaling
- [`examples/complet-parten5`](./examples/complet-parten5): Pattern 5 example
  with a load-balanced edge tier and unexposed internal services

## Examples

The shipped examples assume the network, IAM, security groups, target groups,
listener rules, namespaces, and log groups already exist. That keeps the
examples aligned with this module's actual scope and avoids hiding critical
production dependencies inside example-only infrastructure.
