# ec2

The EC2 launch type counterpart to [`../simple`](../simple): one service running
on EC2 container instances instead of Fargate.

## What differs from Fargate

Capacity. Fargate has none to manage; EC2 needs registered container instances
before ECS can place a task. One entry in `ec2_capacity_providers` builds the
whole chain:

```
launch template -> Auto Scaling group -> ECS capacity provider
```

ECS managed scaling then drives instance count from task demand, and managed
termination protection stops the Auto Scaling group terminating an instance
that is still running tasks.

Everything else the module creates for a Fargate service — task definition,
service, autoscaling policies, CloudWatch alarms — is identical.

## What this example creates

- ECS cluster
- launch template using the current ECS-optimized AMI from SSM, with IMDSv2
  required and an encrypted root volume
- Auto Scaling group with scale-in protection
- ECS capacity provider with managed scaling and managed draining
- container instance IAM role (`AmazonEC2ContainerServiceforEC2Role` +
  `AmazonSSMManagedInstanceCore`) and instance profile
- container instance security group
- one task definition and service on the `bridge` network mode
- CPU target-tracking autoscaling and CloudWatch alarms

## Prerequisites

Existing resources, passed in as variables:

- VPC and private subnets with a NAT or VPC endpoint route, so the ECS agent
  can reach ECS and ECR
- an ALB security group, allowed inbound to the container instances
- a target group with **`target_type = "instance"`** — see below
- task execution role and task role ARNs
- a CloudWatch log group at `/ecs/<cluster_name>/app`

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

terraform output capacity_provider_names
terraform output deployment_summary
```

## Notes worth reading before you adapt this

**Target group `target_type` must match the network mode.** `instance` for
`bridge` and `host`, `ip` for `awsvpc`. This is the single most common EC2
wiring mistake, and it fails at apply.

**`hostPort = 0`** asks Docker for an ephemeral host port, which is what lets
several copies of a bridge-mode task share one instance. A fixed `hostPort`
caps you at one task per instance and produces confusing placement failures.

**bridge and host services must not set `subnets` or `security_groups`.** Those
are `awsvpc`-only; tasks share the container instance ENI instead. The module
omits the `network_configuration` block for non-awsvpc services accordingly.

**`minimum_healthy_percent = 50`, not 100.** EC2 capacity is finite, so ECS
needs to free host ports before it can place replacements. Leaving it at 100
on a full cluster deadlocks the deployment.

**ECS owns the Auto Scaling group's `desired_capacity`.** The module ignores
changes to it — managed scaling sets it from task demand, and declaring it in
Terraform would fight ECS on every plan.

## Going further

For the full EC2 deployment matrix — DAEMON scheduling, Spot capacity via
mixed instances, blue/green and canary on EC2, `awsvpc` vs `bridge` side by
side — see
[`ecs-deployment-patterns/examples/ec2-all-deployment-types`](../../../../ecs-deployment-patterns/examples/ec2-all-deployment-types/).
