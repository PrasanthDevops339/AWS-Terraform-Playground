# terraform-aws-ecs

Terraform module for one ECS cluster and one or more ECS services, defined from
a single `container_config` map. Supports both launch types and every
deployment type ECS offers.

> Renamed from `terraform-aws-ecs-fargate`. The module now covers the EC2
> launch type as well, so the old name understated its scope. Existing callers
> are unaffected: `launch_type_default` is `FARGATE`, and every new input has a
> default that reproduces the previous behaviour.

## Scope

This module is intentionally opinionated:

- one shared ECS cluster
- one or more ECS services and task definitions
- optional EC2 container instance capacity, built as
  launch template -> Auto Scaling group -> ECS capacity provider
- external network, IAM, log groups, and load balancer resources

It supports multi-tier applications by treating each key in `container_config`
as an independent service boundary. A typical shape is `frontend`, `api`, and
`worker` on the same cluster.

This module is not a drop-in mirror of
`terraform-aws-modules/terraform-aws-ecs`. It covers the ECS features used by
this repository and keeps the surrounding infrastructure explicit instead of
auto-creating everything inside the module.

## The deployment matrix

Launch type and deployment type are independent choices. Every cell below is
supported, and worked examples of each live in
[`ecs-deployment-patterns`](../../ecs-deployment-patterns/).

| Deployment type | Selected with | Fargate | EC2 |
| --- | --- | :---: | :---: |
| Rolling update | `deployment_configuration.strategy = "ROLLING"` | yes | yes |
| Blue/green (ECS-native) | `strategy = "BLUE_GREEN"` | yes | yes |
| Linear traffic shift | `strategy = "LINEAR"` | yes | yes |
| Canary traffic shift | `strategy = "CANARY"` | yes | yes |
| External / task sets | `deployment_controller.type = "EXTERNAL"` | yes | yes |
| DAEMON scheduling | `service.scheduling_strategy = "DAEMON"` | no | yes |

`DAEMON` is the one shape Fargate cannot express: it runs one task per
container instance, and Fargate has no instances. The module rejects that
combination at plan time rather than letting the apply fail.

Two axes are worth keeping straight:

- **`deployment_controller`** decides *who* performs the deployment - `ECS` or
  an external system via `CreateTaskSet`.
- **`deployment_configuration.strategy`** decides *how* ECS shifts traffic, and
  is only read by the `ECS` controller.

CodeDeploy is not supported. All four strategies above are performed natively
by ECS, so the module contains no CodeDeploy application, deployment group,
AppSpec or service role. `deployment_controller.type = "CODE_DEPLOY"` fails
validation rather than silently creating nothing.

## Choosing a launch type

| | Fargate | EC2 |
| --- | --- | --- |
| Capacity | none to manage | you run the Auto Scaling group |
| Network modes | `awsvpc` only | `awsvpc`, `bridge`, `host`, `none` |
| Task sizing | required per task | per task or per container |
| GPUs, custom AMIs, Docker volumes | no | yes |
| DAEMON scheduling | no | yes |
| Bin-packing / placement control | no | yes |

Set it per service with `service.launch_type`, or module-wide with
`launch_type_default`. Supplying a `capacity_provider_strategy` instead of a
launch type is also supported - the two are mutually exclusive in the ECS API,
and the module drops `launch_type` for you rather than letting the apply fail.

## Version Requirements

- Terraform `>= 1.5.7`
- AWS provider `~> 6.62`

`6.62` is the floor the module is schema-verified against. The ECS-native
`LINEAR` and `CANARY` strategies and
`load_balancer.advanced_configuration.test_listener_rule` are what set it -
earlier 6.x releases fail to plan.

## What The Module Manages

- ECS cluster
- ECS cluster settings and optional managed storage configuration
- cluster default capacity provider strategy
- ECS task definitions
- ECS services
- ECS-native deployment strategies: `ROLLING`, `BLUE_GREEN`, `LINEAR`,
  `CANARY`
- the EXTERNAL deployment controller for task-set-driven releases
- `REPLICA` and `DAEMON` scheduling strategies
- optional EC2 capacity: launch template, Auto Scaling group (on-demand or
  mixed-instances/Spot), capacity provider, instance role and security group
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
  source = "./terraform-aws-ecs"

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

Every deployment is performed natively by ECS. There is no CodeDeploy path.

- `ROLLING` works with a normal target group or with no target group at all
- `BLUE_GREEN`, `LINEAR`, and `CANARY` require advanced LB wiring
- non-rolling traffic shifting requires
  `target_groups[].alternate_target_group_arn`
- non-rolling traffic shifting requires
  `target_groups[].production_listener_rule`
- `target_groups[].test_listener_rule` is optional, for validating green before
  the cutover
- the IAM role ECS assumes to reweight the listener rule is created for you;
  set `service.deployment_configuration.ecs_alb_service_role_arn` only to
  supply your own

All three deployment controllers are maintained paths, each backed by its own
`aws_ecs_service` resource because `lifecycle.ignore_changes` cannot be
computed:

| Resource | Used for | Ignores |
| --- | --- | --- |
| `aws_ecs_service.main` | ECS controller, Terraform deploys | `desired_count` |
| `aws_ecs_service.main_unmanaged_td` | ECS controller, pipeline deploys | `desired_count`, `task_definition` |
| `aws_ecs_service.external` | `EXTERNAL` controller | `desired_count` |

`main` deliberately does **not** ignore `task_definition`. Terraform performs
the deployment for those services, so ignoring it would make every image bump a
silent no-op. Opt into the ignoring variant per service with
`service.ignore_task_definition_changes = true` when a pipeline outside
Terraform rolls the image.

## Deploying without CodeDeploy

`BLUE_GREEN`, `LINEAR` and `CANARY` are ECS-native: ECS performs the deployment
itself and no CodeDeploy application, deployment group or AppSpec is involved.
A service needs three load balancer inputs and a strategy:

```hcl
service = {
  deployment_configuration = {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = 5
  }

  target_groups = [{
    target_group_arn           = aws_lb_target_group.blue.arn
    alternate_target_group_arn = aws_lb_target_group.green.arn
    production_listener_rule   = aws_lb_listener_rule.production.arn
    test_listener_rule         = aws_lb_listener_rule.test.arn  # optional
    container_name             = "app"
    container_port             = 8080
  }]
}
```

The module creates the **ECS infrastructure IAM role** ECS assumes to reweight
that listener rule, because `advanced_configuration.role_arn` is required by
the provider and there is nothing useful for the caller to decide about it. The
same role picks up the volumes policy when a service declares `ebs_volumes`,
and the VPC Lattice policy when it declares `vpc_lattice_configurations`.

Set `deployment_configuration.ecs_alb_service_role_arn` to use your own role,
or `create_infrastructure_iam_role = false` to require one everywhere.

Note that the production listener rule's weights are owned by ECS after the
first deployment. Guard the rule with
`lifecycle { ignore_changes = [action] }` or Terraform will fight it.

## EC2 capacity

Set `ec2_capacity_providers` to give the cluster container instances. Each
entry builds a launch template, an Auto Scaling group and an ECS capacity
provider, wired together with managed scaling and managed draining.

```hcl
ec2_capacity_providers = {
  ondemand = {
    instance_type = "m6i.large"
    vpc_id        = var.vpc_id
    subnet_ids    = var.private_subnet_ids
    min_size      = 2
    max_size      = 12
  }

  # A non-empty instance_types_override switches the ASG to a mixed instances
  # policy, which is how Spot capacity is diversified across pools.
  spot = {
    vpc_id                                   = var.vpc_id
    subnet_ids                               = var.private_subnet_ids
    instance_types_override                  = ["m6i.large", "m6a.large", "m5.large"]
    on_demand_percentage_above_base_capacity = 0
    min_size                                 = 0
    max_size                                 = 20
  }
}
```

Services then name a provider from the `capacity_provider_names` output:

```hcl
service = {
  launch_type = "EC2"
  capacity_provider_strategy = [
    { capacity_provider = module.ecs.capacity_provider_names["ondemand"], weight = 1 },
  ]
}
```

Notes that matter in practice:

- `managed_termination_protection = "ENABLED"` requires
  `protect_from_scale_in` on the ASG. The module sets it for you.
- ECS managed scaling owns ASG `desired_capacity`, so the module ignores
  changes to it. Setting it in Terraform would fight ECS on every plan.
- Target group `target_type` must match the network mode: `instance` for
  `bridge` and `host`, `ip` for `awsvpc`.

## Testing

`tests/deployment_matrix.tftest.hcl` exercises the launch-type and
deployment-type derivation against mocked AWS providers, so it needs no
credentials and costs nothing:

```bash
terraform init -backend=false
terraform test
```

## Current Gaps

- no ECS Managed Instances capacity provider (`managed_instances_provider`);
  only Auto Scaling group backed providers are built
- Service Connect test traffic rules are not surfaced
- no integrated creation of IAM roles, security groups, target groups, or log
  groups

## Documentation Map

- [`USER_GUIDE.md`](./USER_GUIDE.md): usage guide for multi-tier patterns and
  deployment strategies
- [`ADVANCED_FEATURES.md`](./ADVANCED_FEATURES.md): focused reference for
  Service Connect, traffic shifting, autoscaling, and task definition options
| Example | Shows |
| --- | --- |
| [`examples/simple`](./examples/simple) | Minimal single Fargate service |
| [`examples/ec2`](./examples/ec2) | EC2 launch type with an Auto Scaling group backed capacity provider |
| [`examples/blue-green-deployment`](./examples/blue-green-deployment) | ECS-native `BLUE_GREEN`, plus how to switch to `LINEAR` / `CANARY` |
| [`examples/external-deployment`](./examples/external-deployment) | `EXTERNAL` controller with a real `aws_ecs_task_set` |
| [`examples/multiple-services`](./examples/multiple-services) | Four services from a shared base via `merge()` |
| [`examples/service-connect-tls`](./examples/service-connect-tls) | Service Connect with TLS from AWS Private CA |
| [`examples/complete`](./examples/complete) | Three tiers with Service Connect, canary, and autoscaling |
| [`examples/pattern5`](./examples/pattern5) | Load-balanced edge tier with unexposed internal services |

Operational guidance for all eight — deploy, verify, troubleshoot, roll back,
tear down — is in
[`examples/RUNBOOK.md`](./examples/RUNBOOK.md).

## Examples

The examples in this directory show how to **call** the module: one per shape
of consumer, with the network, IAM, security groups, target groups, listener
rules, namespaces, and log groups passed in as inputs. That keeps them aligned
with the module's actual scope and avoids hiding critical production
dependencies inside example-only infrastructure.

For the **deployment matrix** - every launch type crossed with every deployment
type, including DAEMON scheduling, Spot capacity, and a self-contained
blue/green stack that builds its own ALB - see
[`ecs-deployment-patterns`](../../ecs-deployment-patterns/). Those examples
consume this module; there is no second implementation of the ECS logic.
