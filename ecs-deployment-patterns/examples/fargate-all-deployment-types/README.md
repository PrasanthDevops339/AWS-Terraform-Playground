# fargate-all-deployment-types

Six services on one Fargate cluster, each demonstrating a different deployment
type. Every deployment is performed natively by ECS - no CodeDeploy.

| Service | Controller | Strategy | Point |
| --- | --- | --- | --- |
| `rolling` | `ECS` | `ROLLING` | In-place replacement with a circuit breaker and CPU autoscaling |
| `blue_green` | `ECS` | `BLUE_GREEN` | Full green fleet, 10 minute bake, then a 100% cut |
| `linear` | `ECS` | `LINEAR` | 20% of traffic every 3 minutes, with alarm rollback |
| `canary` | `ECS` | `CANARY` | 10% canary for 15 minutes, plus an optional Lambda hook |
| `external` | `EXTERNAL` | n/a | Service shell only; task sets created by your own system |
| `spot_worker` | `ECS` | `ROLLING` | FARGATE_SPOT via a capacity provider strategy, with an on-demand base |

`DAEMON` scheduling is absent because it needs container instances. See
[`../ec2-all-deployment-types`](../ec2-all-deployment-types/).

## Prerequisites

Existing resources, passed in as variables:

- VPC, private subnets, and a task security group
- task execution role and task role ARNs
- blue and green target groups with `target_type = "ip"`
- an ALB listener, plus the listener **rule** ARN that ECS reweights

The IAM role ECS assumes to reweight that rule is created by the module, so it
is not in the list above.
- CloudWatch log groups under `/ecs/<cluster_name>/`

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan

terraform output deployment_summary
```

## Notes

- `production_listener_rule` is a listener **rule** ARN, not a listener ARN.
  Passing a listener ARN fails at apply, not at plan.
- Alarm-based rollback needs the alarms to exist first. Apply once with
  `rollback_alarm_names = []`, then feed back the `alarm_names_for_rollback`
  output.
- `spot_worker` sets `capacity_provider_strategy` instead of `launch_type`. The
  two are mutually exclusive in the ECS API; the module drops `launch_type`
  rather than letting the apply fail.
