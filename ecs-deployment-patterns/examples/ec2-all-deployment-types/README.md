# ec2-all-deployment-types

An EC2-backed cluster with two capacity providers, running every deployment
type ECS supports — including `DAEMON`, which Fargate cannot express.

All traffic shifting is native to ECS; there is no CodeDeploy in this stack.

## Capacity

| Provider | Shape | For |
| --- | --- | --- |
| `ondemand` | `m6i.large`, min 2 / max 12 | Anything serving traffic |
| `spot` | Mixed instances across 4 types, min 0 / max 20 | Interruption-tolerant batch |

Each builds launch template → Auto Scaling group → ECS capacity provider. ECS
managed scaling then drives instance count from task demand.

## Services

| Service | Network mode | Deployment | Point |
| --- | --- | --- | --- |
| `rolling_bridge` | `bridge` | `ROLLING` | Ephemeral host ports, spread-then-binpack placement |
| `rolling_awsvpc` | `awsvpc` | `ROLLING` | Per-task ENI, same as Fargate |
| `blue_green` | `awsvpc` | `BLUE_GREEN` | Identical to the Fargate form |
| `linear` | `awsvpc` | `LINEAR` | 25% every 2 minutes |
| `canary` | `awsvpc` | `CANARY` | 5% for 20 minutes |
| `daemon` | `host` | `DAEMON` | One log agent per instance, kept off Spot |
| `external` | `bridge` | `EXTERNAL` | Task sets managed outside Terraform |
| `spot_batch` | `bridge` | `ROLLING` | Pinned to Spot, binpacked |

## Prerequisites

Existing resources, passed in as variables:

- VPC and private subnets
- ALB security group, and a security group for `awsvpc` task ENIs
- task execution role and task role ARNs (the ECS infrastructure role is created by the module)
- **two kinds of target group**: one `instance` type for the bridge service,
  and blue/green `ip` type groups for the awsvpc services
- an ALB listener and the listener rule ARN ECS reweights

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

terraform output deployment_summary
terraform output capacity_provider_names
```

## Notes

- Target group `target_type` must match the network mode: `instance` for
  `bridge` and `host`, `ip` for `awsvpc`. This is the main wiring difference
  from Fargate.
- `hostPort = 0` in bridge mode asks Docker for an ephemeral port, which is
  what lets several copies of a task share one instance. A fixed `hostPort`
  caps you at one task per instance.
- `minimum_healthy_percent = 50` on the bridge service is deliberate: EC2
  capacity is finite, so ECS needs to free host ports before placing
  replacements.
- The `daemon` service carries a placement constraint keeping it off Spot
  instances, which disappear mid-flush.
