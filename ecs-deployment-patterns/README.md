# ecs-deployment-patterns

Worked examples of **every ECS launch type crossed with every ECS deployment
type**, built on the
[`terraform-aws-ecs`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/) module.

> Previously `ECS-POC`. It was a standalone fork of the module that had drifted
> out of sync and no longer passed `terraform validate`. It is now examples
> only: each directory is a root module that calls `terraform-aws-ecs`
> directly, so there is one implementation of the ECS logic, not two.

## The matrix

| Deployment type | Who deploys | Fargate | EC2 |
| --- | --- | :---: | :---: |
| Rolling update | ECS | yes | yes |
| Blue/green (ECS-native) | ECS | yes | yes |
| Linear traffic shift | ECS | yes | yes |
| Canary traffic shift | ECS | yes | yes |
| External / task sets | Your system | yes | yes |
| DAEMON scheduling | ECS | **no** | yes |

`DAEMON` runs one task per container instance. Fargate has no instances, so the
combination does not exist — for a Fargate workload the equivalent is a sidecar
in the task definition. The module rejects it at plan time rather than letting
the apply fail after several minutes.

## Examples

| Directory | What it shows |
| --- | --- |
| [`examples/minimal-fargate`](examples/minimal-fargate/) | Smallest working service. One Fargate task, no load balancer, default rolling deployment. Start here. |
| [`examples/fargate-native-blue-green`](examples/fargate-native-blue-green/) | **Blue/green with no CodeDeploy.** Self-contained: builds the ALB, both target groups and both listener rules alongside the service. The clearest read of the traffic-shifting path. |
| [`examples/fargate-all-deployment-types`](examples/fargate-all-deployment-types/) | Six services on one Fargate cluster: rolling, blue/green, linear, canary, external, and a FARGATE_SPOT worker. |
| [`examples/ec2-all-deployment-types`](examples/ec2-all-deployment-types/) | Eight services on an EC2 cluster with two capacity providers: the same deployment types plus DAEMON scheduling, bridge vs awsvpc networking, placement strategies and Spot batch. |
| [`examples/mixed-fargate-ec2`](examples/mixed-fargate-ec2/) | One cluster, both launch types. Fargate API, GPU inference on EC2, Spot batch, and a DAEMON node agent covering the EC2 fleet only. |

## Where the other examples live

These examples cover the **deployment matrix**. For plain "how do I call the
module" usage, see the module's own examples:

| Example | Shows |
| --- | --- |
| [`terraform-aws-ecs/examples/simple`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/simple/) | Minimal single Fargate service |
| [`terraform-aws-ecs/examples/ec2`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/ec2/) | Minimal EC2 service with a capacity provider |
| [`terraform-aws-ecs/examples/complete`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/complete/) | Three tiers, Service Connect, canary, autoscaling |
| [`terraform-aws-ecs/examples/blue-green-deployment`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/blue-green-deployment/) | ECS-native blue/green, target groups passed in |
| [`terraform-aws-ecs/examples/external-deployment`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/external-deployment/) | EXTERNAL controller with a real task set |
| [`terraform-aws-ecs/examples/multiple-services`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/multiple-services/) | Four services from a shared base |
| [`terraform-aws-ecs/examples/service-connect-tls`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/service-connect-tls/) | Service Connect with TLS from Private CA |
| [`terraform-aws-ecs/examples/pattern5`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/pattern5/) | Load-balanced edge tier, unexposed internal services |

## The two axes people conflate

**`deployment_controller`** decides *who* performs the deployment:

- `ECS` — ECS does it. Terraform triggers it by updating the service.
- `EXTERNAL` — your system does it via `CreateTaskSet`. ECS creates only the
  service shell.

CodeDeploy is deliberately not supported. Blue/green, linear and canary are all
performed natively by ECS, so there is no CodeDeploy application, deployment
group, AppSpec or service role anywhere in this repo. Passing
`deployment_controller.type = "CODE_DEPLOY"` fails validation with a message
pointing at the native strategies.

**`deployment_configuration.strategy`** decides *how* ECS shifts traffic, and is
read **only** by the `ECS` controller:

- `ROLLING` — replace tasks in place, bounded by min-healthy/max percentages.
- `BLUE_GREEN` — stand up a full green fleet, bake, shift 100%, tear down blue.
- `LINEAR` — shift `step_percent` at a time, pausing `step_bake_time_in_minutes`.
- `CANARY` — shift `canary_percent`, hold `canary_bake_time_in_minutes`, then
  shift the rest.

## Choosing a launch type

| | Fargate | EC2 |
| --- | --- | --- |
| Capacity | none to manage | you run the Auto Scaling group |
| Network modes | `awsvpc` only | `awsvpc`, `bridge`, `host`, `none` |
| Task sizing | required per task | per task or per container |
| GPUs, custom AMIs, Docker volumes | no | yes |
| DAEMON scheduling | no | yes |
| Bin-packing / placement control | no | yes |
| Cost model | per task, per second | per instance, so packing pays |

## Wiring that trips people up

**Traffic shifting needs three inputs.** `BLUE_GREEN`, `LINEAR` and `CANARY`
each need all of:

```hcl
target_groups = [{
  target_group_arn           = ...  # blue
  alternate_target_group_arn = ...  # green
  production_listener_rule   = ...  # the RULE ARN, not the listener ARN
}]
```

The IAM role ECS assumes to reweight that rule is created for you. Supply
`service.deployment_configuration.ecs_alb_service_role_arn` only to reuse a
role you already manage.

`production_listener_rule` is a **listener rule** ARN. Passing a listener ARN is
the most common mistake here, and it fails at apply, not at plan.

**The production listener rule's weights drift, by design.** A completed
blue/green deployment leaves green at 100 and blue at 0, and the pair swaps
roles on the next release. Put `lifecycle { ignore_changes = [action] }` on the
rule, or every plan after a deployment will try to shove traffic back onto the
target group that is no longer live. The upstream `terraform-aws-modules/alb`
module does not do this for you. See
[`examples/fargate-native-blue-green`](examples/fargate-native-blue-green/).

**Target group `target_type` must match the network mode.** `ip` for `awsvpc`
(all Fargate, and EC2 when you choose it), `instance` for `bridge` and `host`.
The EC2 example needs both kinds, which is why it takes two target group inputs.

**Alarm-based rollback is a two-pass apply if you use this module's own
alarms.** The alarms have to exist before a deployment can reference them.
Apply once with `rollback_alarm_names = []`, then feed the
`alarm_names_for_rollback` output back in.

## Running an example

Every example takes existing network, IAM and load balancer resources as
inputs. That is deliberate: it keeps the examples about ECS deployment
behaviour instead of hiding production dependencies inside example-only
infrastructure.

```bash
cd examples/fargate-all-deployment-types

terraform init
terraform fmt -check
terraform validate

# Always review a plan artifact rather than applying straight from a fresh plan.
terraform plan -out=tfplan
terraform show tfplan

terraform apply tfplan
```

The `deployment_summary` output is the fastest check that each service resolved
to the shape you intended:

```text
+ deployment_summary = {
    + canary = {
        + deployment_controller = "ECS"
        + deployment_strategy   = "CANARY"
        + launch_type           = "FARGATE"
        + network_mode          = "awsvpc"
        + scheduling_strategy   = "REPLICA"
        + shifts_traffic        = true
      }
    ...
```

## Validating changes to the underlying module

The module ships a mocked-provider test suite covering this whole matrix. It
needs no AWS credentials and costs nothing:

```bash
cd ../Terrafrom-AWS-Prasanth/terraform-aws-ecs
terraform init -backend=false
terraform test
```

## Related

- [`examples/RUNBOOK.md`](./examples/RUNBOOK.md) — per-example runbook: deploy, verify, operate each deployment type, cost control, teardown
- [`RUNBOOK.md`](./RUNBOOK.md) — general ECS incident commands for any cluster
- [`terraform-aws-ecs`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/README.md) — the module these examples consume
- [`USER_GUIDE.md`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/USER_GUIDE.md) — multi-tier usage guide
- [`ADVANCED_FEATURES.md`](../Terrafrom-AWS-Prasanth/terraform-aws-ecs/ADVANCED_FEATURES.md) — Service Connect, autoscaling, task definition options
