# Runbook — ecs-deployment-patterns examples

Operational reference for the five examples in this directory.

These examples exist to exercise the **deployment matrix**: every ECS launch
type crossed with every deployment type. They are denser than the module's own
examples — several deployment strategies run side by side on one cluster — so
most of this runbook is about telling them apart at runtime.

- Module usage examples: [`terraform-aws-ecs/examples/RUNBOOK.md`](../../Terrafrom-AWS-Prasanth/terraform-aws-ecs/examples/RUNBOOK.md)
- General ECS incident commands: [`../RUNBOOK.md`](../RUNBOOK.md)

---

## Contents

- [Before you start](#before-you-start)
- [Which example am I looking at](#which-example-am-i-looking-at)
- [Standard workflow](#standard-workflow)
- [Example reference](#example-reference)
  - [minimal-fargate](#minimal-fargate)
  - [fargate-native-blue-green](#fargate-native-blue-green)
  - [fargate-all-deployment-types](#fargate-all-deployment-types)
  - [ec2-all-deployment-types](#ec2-all-deployment-types)
  - [mixed-fargate-ec2](#mixed-fargate-ec2)
- [Operating each deployment type](#operating-each-deployment-type)
- [Cost control](#cost-control)
- [Teardown](#teardown)

---

## Before you start

**Runtime and provider.** Terraform `>= 1.5.7`, AWS provider `~> 6.62`. The
`LINEAR` and `CANARY` strategies and `test_listener_rule` do not exist in
earlier 6.x releases.

**Account alias required.** The module derives every name from
`data.aws_iam_account_alias`. Without an alias set, names come out malformed.

```bash
aws iam list-account-aliases --query 'AccountAliases[0]' --output text
```

**These examples are not free.** `ec2-all-deployment-types` alone launches two
Auto Scaling groups and eight services. Read [Cost control](#cost-control)
before applying any of them to a real account.

**Local state by default.** Add a remote backend before using these anywhere
shared.

---

## Which example am I looking at

| Example | Cluster shape | Services | Costs money while idle |
| --- | --- | --- | --- |
| `minimal-fargate` | Fargate | 1 | Minimal — 1 task |
| `fargate-native-blue-green` | Fargate | 1 | Low — 2 tasks + an ALB it creates |
| `fargate-all-deployment-types` | Fargate | 6 | Moderate — ~17 tasks |
| `ec2-all-deployment-types` | EC2, 2 capacity providers | 8 | **High** — min 2 on-demand instances, always on |
| `mixed-fargate-ec2` | Fargate + EC2 (GPU, Spot) | 4 | **High** — GPU instances |

`fargate-native-blue-green` is the only one that builds its own ALB. The rest
take load balancer resources as inputs.

---

## Standard workflow

```bash
cd <example>

terraform init
terraform fmt -check
terraform validate

terraform plan -out=tfplan
terraform show tfplan | less

terraform apply tfplan
```

### The first command to run after any apply

```bash
terraform output deployment_summary
```

Every example in this directory exposes it, and on the multi-service ones it is
the only practical way to confirm each service got the shape you intended:

```
+ deployment_summary = {
    + canary = {
        + capacity_providers    = []
        + deployment_controller = "ECS"
        + deployment_strategy   = "CANARY"
        + launch_type           = "FARGATE"
        + network_mode          = "awsvpc"
        + scheduling_strategy   = "REPLICA"
        + shifts_traffic        = true
      }
    ...
```

Read it before touching AWS. A wrong `deployment_strategy` or `launch_type`
here is a config bug, and no amount of console digging will explain it.

---

## Example reference

### minimal-fargate

One Fargate task, no load balancer, default `ROLLING`.

**Required inputs:** `vpc_id`, `private_subnet_ids`,
`service_security_group_id`, `execution_role_arn`, `task_role_arn`

**Service key:** `app`

Use this to prove your VPC, subnets, IAM roles and image pull path work before
running anything more complex. If `minimal-fargate` will not start a task,
nothing else in this directory will either.

```bash
export CLUSTER=$(terraform output -raw cluster_name)
aws ecs describe-services --cluster "$CLUSTER" \
  --services "$(terraform output -json service_names | jq -r '.app')" \
  --query 'services[0].{Running:runningCount,Desired:desiredCount}'
```

---

### fargate-native-blue-green

The only self-contained example: it builds the ALB, both target groups and both
listener rules alongside the service.

**Required inputs:** `vpc_id`, `vpc_cidr_block`, `public_subnet_ids`,
`private_subnet_ids`, `ingress_cidr`, `test_ingress_cidr`,
`execution_role_arn`, `task_role_arn`

**Service key:** `app`

**Two endpoints:**

```bash
ALB=$(terraform output -raw alb_dns_name)
curl "http://$ALB/"       # port 80  — production, currently-live version
curl "http://$ALB:8080/"  # port 8080 — test listener, the green task set
```

**Run a deployment and watch traffic shift:**

```bash
# 1. Change the image, then apply.
terraform apply -var="container_image=<new-image>"

# 2. Watch the rule weights move from blue=100/green=0 to blue=0/green=100.
RULE=$(terraform output -raw production_listener_rule_arn)
watch -n5 "aws elbv2 describe-rules --rule-arns $RULE \
  --query 'Rules[0].Actions[0].ForwardConfig.TargetGroups[*].{TG:TargetGroupArn,Weight:Weight}' \
  --output table"
```

**Expect drift on the listener rule after the first deployment — this is
correct.** ECS owns those weights, and the example guards the rule with
`lifecycle { ignore_changes = [action] }`. If you copy this pattern into a
stack that uses `terraform-aws-modules/alb`, you must add that guard yourself;
the upstream module does not.

**Rollback during the bake window:** re-apply the previous image. Outside the
bake window blue is already gone, so it is a normal forward deployment.

---

### fargate-all-deployment-types

Six services on one Fargate cluster, one per deployment type.

**Required inputs:** `vpc_id`, `private_subnet_ids`,
`service_security_group_id`, `execution_role_arn`, `task_role_arn`,
`blue_target_group_arn`, `green_target_group_arn`,
`production_listener_rule_arn`

**Service keys and what each is for:**

| Key | Strategy | Watch for |
| --- | --- | --- |
| `rolling` | `ROLLING` | Completes in a couple of minutes |
| `blue_green` | `BLUE_GREEN` | 10 minute bake |
| `linear` | `LINEAR` | 20% every 3 min → ~15 min total |
| `canary` | `CANARY` | 10% for 15 min, then the rest |
| `external` | `EXTERNAL` controller | No task definition on the service |
| `spot_worker` | `ROLLING` on FARGATE_SPOT | Placed by capacity provider strategy, not launch type |

**All four traffic-shifting services share one blue/green target group pair.**
That is fine for demonstrating the strategies, but it means you should deploy
**one at a time** — two concurrent traffic shifts against the same listener rule
will fight each other.

```bash
# Deploy one service only.
aws ecs update-service --cluster "$CLUSTER" \
  --service "$(terraform output -json service_names | jq -r '.canary')" \
  --force-new-deployment
```

**Confirm `spot_worker` is actually on Spot:**

```bash
terraform output -json deployment_summary | jq '.spot_worker.capacity_providers'
# ["FARGATE","FARGATE_SPOT"] — and launch_type is null, because the two conflict
```

**Confirm `external` has no task definition on the service:**

```bash
aws ecs describe-services --cluster "$CLUSTER" \
  --services "$(terraform output -json service_names | jq -r '.external')" \
  --query 'services[0].{Controller:deploymentController.type,TaskDef:taskDefinition}'
# TaskDef should be null — task sets carry it
```

---

### ec2-all-deployment-types

Eight services on an EC2 cluster with two capacity providers. The densest
example here, and the most expensive.

**Required inputs:** `vpc_id`, `private_subnet_ids`, `alb_security_group_id`,
`service_security_group_id`, `execution_role_arn`, `task_role_arn`,
`instance_blue_target_group_arn`, `ip_blue_target_group_arn`,
`ip_green_target_group_arn`, `production_listener_rule_arn`

**You need two kinds of target group.** This is the main wiring difference from
Fargate and the most common failure:

| Target group | `target_type` | Used by |
| --- | --- | --- |
| `instance_blue_target_group_arn` | `instance` | `rolling_bridge` (bridge network mode) |
| `ip_blue` / `ip_green` | `ip` | all `awsvpc` services |

**Check capacity before anything else.** Every service failure on this example
traces back to capacity first:

```bash
export CLUSTER=$(terraform output -raw cluster_name)

aws ecs describe-clusters --clusters "$CLUSTER" \
  --query 'clusters[0].{Instances:registeredContainerInstancesCount,Running:runningTasksCount,Pending:pendingTasksCount}'

terraform output capacity_provider_names
terraform output container_instance_autoscaling_group_names
```

**Service keys:**

| Key | Network mode | Notes |
| --- | --- | --- |
| `rolling_bridge` | `bridge` | Ephemeral host ports; needs the `instance` target group |
| `rolling_awsvpc` | `awsvpc` | Per-task ENI, behaves like Fargate |
| `blue_green` | `awsvpc` | Traffic shifting on EC2 |
| `linear` | `awsvpc` | 25% every 2 min |
| `canary` | `awsvpc` | 5% for 20 min |
| `daemon` | `host` | One task per instance; **no desired count** |
| `external` | `bridge` | Task sets |
| `spot_batch` | `bridge` | Pinned to the Spot capacity provider |

**DAEMON verification** — running count should equal the number of instances
that satisfy its placement constraint (it is deliberately kept off Spot):

```bash
aws ecs describe-services --cluster "$CLUSTER" \
  --services "$(terraform output -json service_names | jq -r '.daemon')" \
  --query 'services[0].{Running:runningCount,Scheduling:schedulingStrategy}'
```

If running count is 0 but instances are registered, the placement constraint
excluded all of them.

**"unable to place a task" on this example**, in likelihood order:

1. No instance has enough remaining CPU/memory — the eight services compete.
2. `bridge` host port conflict — only `hostPort = 0` allows co-location.
3. `awsvpc` ENI limit reached for the instance type.
4. Placement constraint matches nothing (the `daemon` service excludes Spot).

```bash
aws ecs describe-services --cluster "$CLUSTER" --services <service> \
  --query 'services[0].events[0:5].message' --output text
```

**Spot interruptions are expected** on `spot_batch`. `capacity_rebalance` and
`managed_draining` handle them; tasks restart elsewhere. Do not treat a
restarted Spot task as an incident.

---

### mixed-fargate-ec2

One cluster, both launch types. The realistic end state.

**Required inputs:** `vpc_id`, `private_subnet_ids`,
`service_security_group_id`, `inference_image`, `batch_image`,
`execution_role_arn`, `task_role_arn`, `blue_target_group_arn`,
`green_target_group_arn`, `production_listener_rule_arn`

**Service keys:** `api` (Fargate), `gpu_inference` (EC2 GPU), `batch` (EC2
Spot), `node_agent` (EC2 DAEMON)

**Confirm the split is real:**

```bash
terraform output -json deployment_summary | \
  jq 'to_entries[] | {service: .key, launch: .value.launch_type, sched: .value.scheduling_strategy}'
```

`api` must be `FARGATE`; the other three `EC2`. If `gpu_inference` came out
Fargate, it will never place — Fargate has no GPUs.

**`node_agent` covers EC2 instances only.** Fargate tasks have no host to place
a daemon on, so `api` is not monitored by it. That is the architectural point
of the example, not a bug — a Fargate workload needs the agent as a sidecar
inside its own task definition.

**GPU placement failures:**

```bash
# The task requires attribute:ecs.instance-type =~ g5.*
aws ecs describe-container-instances --cluster "$CLUSTER" \
  --container-instances $(aws ecs list-container-instances --cluster "$CLUSTER" --query 'containerInstanceArns[]' --output text) \
  --query 'containerInstances[*].{Id:ec2InstanceId,Type:attributes[?name==`ecs.instance-type`].value|[0]}' \
  --output table
```

The GPU capacity provider has `min_size = 0`, so the first deployment waits for
ECS managed scaling to launch an instance. That takes several minutes — a
pending task here is usually normal, not stuck.

**`gpu_inference` deploys at `0/100`.** GPU capacity is scarce and expensive,
so ECS stops the old task before starting the new one. Expect brief downtime;
this is deliberate, not a misconfiguration.

---

## Operating each deployment type

Applies across examples.

### ROLLING

```bash
aws ecs describe-services --cluster "$CLUSTER" --services <service> \
  --query 'services[0].deployments[*].{Status:status,Rollout:rolloutState,Running:runningCount}'
```

With the circuit breaker enabled, ECS reverts on its own when tasks fail to
stabilise. Without it, a bad image hangs the deployment indefinitely.

### BLUE_GREEN / LINEAR / CANARY

The listener rule weights are the source of truth:

```bash
aws elbv2 describe-rules --rule-arns <production-listener-rule-arn> \
  --query 'Rules[0].Actions[0].ForwardConfig.TargetGroups[*].{TG:TargetGroupArn,Weight:Weight}' \
  --output table
```

Rough timings, so you know what "stuck" looks like:

| Strategy | Time to 100% |
| --- | --- |
| `BLUE_GREEN` | health checks + bake (5–10 min) |
| `LINEAR` 20%/3min | ~15 min + bake |
| `LINEAR` 25%/2min | ~8 min + bake |
| `CANARY` 10%/15min | ~20 min |
| `CANARY` 5%/20min | ~25 min |

**Do not interrupt a traffic shift.** An aborted apply can leave the rule
part-weighted. If you must stop one, force a deployment from the known-good
task definition rather than killing Terraform.

### DAEMON

No desired count, cannot be autoscaled, and only
`deployment_minimum_healthy_percent` applies. Running count follows instance
count.

### EXTERNAL

Terraform owns the service shell only.

```bash
aws ecs describe-services --cluster "$CLUSTER" --services <service> \
  --query 'services[0].taskSets[*].{Id:id,Status:status,Scale:scale,Stability:stabilityStatus}'
```

---

## Cost control

These are demonstration stacks, and two of them are genuinely expensive.

**Before applying:**

```bash
terraform plan -out=tfplan
terraform show -json tfplan | jq -r '
  .resource_changes[]
  | select(.change.actions[] | . == "create")
  | select(.type | test("autoscaling_group|ecs_service|lb$"))
  | "\(.type)  \(.address)"'
```

**Scale everything to zero without destroying:**

```bash
for s in $(terraform output -json service_names | jq -r '.[]'); do
  aws ecs update-service --cluster "$CLUSTER" --service "$s" --desired-count 0 >/dev/null
  echo "scaled to 0: $s"
done
```

EC2 capacity providers then drain instances down to `min_size` on their own. To
release them fully, set `min_size = 0` and apply.

**Worth knowing per example:**

- `ec2-all-deployment-types` sets `min_size = 2` on the on-demand provider —
  those instances run whether or not any task does.
- `mixed-fargate-ec2` uses `g5.xlarge` GPU instances. `min_size = 0`, so they
  only appear on demand, but they are expensive while up.
- `fargate-native-blue-green` creates an ALB, which bills hourly regardless of
  traffic.
- Spot providers (`spot`, `batch`) with `min_size = 0` cost nothing idle.

---

## Teardown

**Always inspect a destroy plan first.** These stacks have interdependencies
that make a blind destroy slow or stuck.

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan | less
terraform apply destroy.tfplan
```

Recommended order for the EC2-backed examples, which otherwise stall:

```bash
# 1. Drain the services.
for s in $(terraform output -json service_names | jq -r '.[]'); do
  aws ecs update-service --cluster "$CLUSTER" --service "$s" --desired-count 0 >/dev/null
done

# 2. Wait for tasks to stop. Managed termination protection keeps instances
#    alive while tasks run, so this is not instant.
aws ecs describe-clusters --clusters "$CLUSTER" \
  --query 'clusters[0].{Running:runningTasksCount,Pending:pendingTasksCount}'

# 3. Then destroy.
terraform apply destroy.tfplan
```

Notes:

- A `DAEMON` service cannot be scaled to zero — it stops when its instances do.
- Capacity providers cannot be detached from a cluster with running tasks.
- The `fargate-native-blue-green` example owns its ALB, target groups and
  listener rules, so destroy removes them. Every other example treats those as
  inputs and leaves them behind.
- Never use `-auto-approve` on a destroy in a shared account.
