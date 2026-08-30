# Runbook — terraform-aws-ecs examples

Operational reference for the eight examples in this directory.

Each example is a root module that calls [`terraform-aws-ecs`](../). They all
take existing network, IAM and load balancer resources as inputs, so nothing
here creates a VPC or an ALB for you.

For the deployment-matrix examples (every launch type crossed with every
deployment type), see
[`ecs-deployment-patterns/examples/RUNBOOK.md`](../../../ecs-deployment-patterns/examples/RUNBOOK.md).
For general ECS incident commands that apply to any cluster, see
[`ecs-deployment-patterns/RUNBOOK.md`](../../../ecs-deployment-patterns/RUNBOOK.md).

---

## Contents

- [Before you start](#before-you-start)
- [Naming: what the module actually creates](#naming-what-the-module-actually-creates)
- [Standard workflow](#standard-workflow)
- [Example reference](#example-reference)
  - [simple](#simple)
  - [ec2](#ec2)
  - [blue-green-deployment](#blue-green-deployment)
  - [external-deployment](#external-deployment)
  - [multiple-services](#multiple-services)
  - [service-connect-tls](#service-connect-tls)
  - [complete](#complete)
  - [pattern5](#pattern5)
- [Cross-cutting troubleshooting](#cross-cutting-troubleshooting)
- [Rollback](#rollback)
- [Teardown](#teardown)

---

## Before you start

**Runtime and provider.** Terraform `>= 1.5.7`, AWS provider `~> 6.62`. The
6.62 floor is not cosmetic: the `LINEAR` and `CANARY` strategies and
`advanced_configuration.test_listener_rule` are absent from earlier 6.x
releases, and `terraform plan` fails on them.

**Credentials.** Every example calls `data.aws_iam_account_alias`, so the
calling principal needs `iam:ListAccountAliases`. **The account must have an
alias set** — without one this data source returns nothing and every resource
name comes out malformed.

```bash
aws iam list-account-aliases --query 'AccountAliases[0]' --output text
```

**Backend.** The examples ship with no backend block, so they default to local
state. Do not run these against a shared or production account without adding a
remote backend first.

```hcl
terraform {
  backend "s3" {
    bucket       = "my-terraform-state"
    key          = "ecs/<example>/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 locking, Terraform 1.10+
  }
}
```

---

## Naming: what the module actually creates

Resource names are derived, not passed in. Knowing the pattern saves you
guessing during an incident:

| Thing | Pattern | Example |
| --- | --- | --- |
| Cluster | `<account_alias>-<cluster_name>` | `acme-simple` |
| Service | `<account_alias>-<service_key>` | `acme-app` |
| Task definition family | `<account_alias>-<service_key>` | `acme-app` |
| EC2 capacity provider | `<account_alias>-<cluster_name>-<cp_key>` | `acme-ec2-default` |
| Infrastructure IAM role | `<account_alias>-<service_key>-infra` | `acme-app-infra` |

The `service_key` is the key in `container_config`, not the container name.

Capture these before you need them:

```bash
export CLUSTER=$(terraform output -raw cluster_name)
terraform output service_name        # or service_names in older examples
```

---

## Standard workflow

Applies to every example.

```bash
cd <example>

terraform init
terraform fmt -check
terraform validate

# Always review a plan artifact rather than applying from a fresh plan.
terraform plan -out=tfplan
terraform show tfplan | less

terraform apply tfplan
```

### First check after any apply

```bash
terraform output deployment_summary
```

This is the fastest confirmation that each service resolved to the shape you
intended — launch type, network mode, scheduling strategy, deployment
controller, and whether it shifts traffic. If something is wrong here, it is
wrong in the config, and no amount of AWS-side debugging will help.

> `simple`, `complete` and `pattern5` predate this output and expose
> `deployment_strategies` instead.

### Watching a deployment

```bash
aws ecs describe-services --cluster "$CLUSTER" --services <service> \
  --query 'services[0].deployments[*].{Status:status,Rollout:rolloutState,Reason:rolloutStateReason,Desired:desiredCount,Running:runningCount}' \
  --output table
```

`rolloutState` is the field that matters: `IN_PROGRESS` → `COMPLETED`, or
`FAILED` if the circuit breaker tripped.

---

## Example reference

### simple

Minimal single Fargate service. Start here.

**Creates:** cluster, one task definition, one service, alarms.

**Required inputs:** `vpc_id`, `subnet_ids`, `service_security_group_id`,
`execution_role_arn`, `task_role_arn`, `target_group_arn`, `container_image`,
`log_group_name`

**Service key:** `app`

**Verify:**

```bash
aws ecs describe-services --cluster "$CLUSTER" --services "$(terraform output -json service_names | jq -r '.app')" \
  --query 'services[0].{Running:runningCount,Desired:desiredCount,Status:status}'
```

**Deploy a new image:** change `container_image`, then `plan` and `apply`.
Terraform registers a new task definition revision and updates the service.
This is the one thing to understand about the module: for ECS-controller
services it does **not** ignore `task_definition`, so an image bump is a real
deployment.

---

### ec2

The EC2 launch type: capacity providers, container instances, bridge
networking.

**Creates:** everything `simple` does, plus a launch template, Auto Scaling
group, ECS capacity provider, instance IAM role and instance security group.

**Required inputs:** `vpc_id`, `subnet_ids`, `alb_security_group_id`,
`target_group_arn`, `execution_role_arn`, `task_role_arn`

**Service key:** `app`

**Verify capacity registered before blaming the service:**

```bash
aws ecs describe-clusters --clusters "$CLUSTER" \
  --query 'clusters[0].{Registered:registeredContainerInstancesCount,Running:runningTasksCount,Pending:pendingTasksCount}'
```

`registeredContainerInstancesCount` of 0 means no instance joined. Check, in
order:

1. The ASG actually launched something:
   ```bash
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names "$(terraform output -json container_instance_autoscaling_group_names | jq -r '.default')" \
     --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:length(Instances)}'
   ```
2. The instance can reach ECS. Private subnets need a NAT route or the
   `ecs-agent`, `ecs-telemetry`, `ecr.api`, `ecr.dkr`, `logs` and `s3` VPC
   endpoints. This is the single most common cause.
3. The agent log on the instance: `/var/log/ecs/ecs-agent.log`, reachable via
   SSM Session Manager (the instance role includes
   `AmazonSSMManagedInstanceCore`).

**Scaling:** ECS managed scaling owns the ASG `desired_capacity`. Terraform
ignores changes to it on purpose. To change capacity bounds, edit `min_size` /
`max_size` and apply — never set `desired_capacity` by hand.

**Target group type:** must be `instance` for this example's `bridge` network
mode. `ip` silently registers nothing.

---

### blue-green-deployment

ECS-native `BLUE_GREEN`. No CodeDeploy.

**Required inputs:** the `simple` set plus `blue_target_group_arn`,
`green_target_group_arn`, `production_listener_rule_arn`

**Service key:** `app`

**Verify the wiring before the first deployment:**

```bash
terraform output deployment_summary          # shifts_traffic must be true
terraform output infrastructure_iam_role_arns # must not be null
```

If `infrastructure_iam_role_arns` is null for `app`, ECS has no role to
reweight the listener rule and the deployment will fail.

**Watch a deployment shift traffic:**

```bash
# The rule ARN is an INPUT to this example, not an output - use the value you
# passed in as production_listener_rule_arn.
RULE=<production-listener-rule-arn>

# Weights move from blue=100/green=0 to blue=0/green=100 during the shift.
aws elbv2 describe-rules --rule-arns "$RULE" \
  --query 'Rules[0].Actions[0].ForwardConfig.TargetGroups[*].{TG:TargetGroupArn,Weight:Weight}' \
  --output table
```

**Enabling alarm rollback is a two-pass apply.** The alarms must exist before a
deployment can reference them:

```bash
terraform apply tfplan                                  # pass 1, empty list
terraform output -json alarm_names_for_rollback         # feed into tfvars
terraform apply -var-file=with-alarms.tfvars            # pass 2
```

**Switching to LINEAR or CANARY:** change only the
`deployment_configuration` block. Target groups, listener rule and IAM role are
identical. See the example's README.

---

### external-deployment

`EXTERNAL` deployment controller with a real `aws_ecs_task_set`.

**Required inputs:** `vpc_id`, `subnet_ids`, `service_security_group_id`,
`container_image`, `log_group_name`, `execution_role_arn`, `task_role_arn`

**Service key:** `app`

**What lives where** — this is the thing to internalise:

| On the service | On the task set |
| --- | --- |
| Controller type, desired count, tags | Task definition, network config, load balancer, scale |

**Verify:**

```bash
terraform output task_set_stability_status   # expect STEADY_STATE

aws ecs describe-services --cluster "$CLUSTER" --services "$(terraform output -json service_name | jq -r '.app')" \
  --query 'services[0].taskSets[*].{Id:id,Status:status,Scale:scale,Stability:stabilityStatus,TaskDef:taskDefinition}' \
  --output table
```

**Deploying:** normally your external system creates a new task set and shifts
`scale` between them. The bootstrap task set here has
`ignore_changes = [scale, task_definition]` precisely so Terraform does not
undo that.

**Do not manage the same task set from both Terraform and the pipeline.** If
the pipeline owns rollouts, set `create_initial_task_set = false` and let it
create every task set.

**Stuck task set:**

```bash
aws ecs describe-task-sets --cluster "$CLUSTER" --service <service> \
  --task-sets <task-set-arn> \
  --query 'taskSets[0].{Stability:stabilityStatus,Reason:stabilityStatusAt,Running:runningCount,Pending:pendingCount}'
```

`wait_until_stable = true` means a broken image fails the **apply** rather than
leaving a task set that never stabilises — expect a 10 minute timeout.

---

### multiple-services

Four services from a shared base: `web`, `api`, `worker`, `scheduler`.

**Required inputs:** three security groups (`web`, `api`, `worker`), four
images, blue/green target groups plus listener rule for `web`, one target group
for `api`, shared roles.

**Service keys:** `web`, `api`, `worker`, `scheduler`

**Verify the deliberate differences survived the merge:**

```bash
terraform output deployment_summary
# web       -> BLUE_GREEN, shifts_traffic = true
# api       -> ROLLING
# worker    -> ROLLING
# scheduler -> ROLLING

terraform output autoscaling_target_resource_id
# scheduler must be ABSENT — a singleton must stay a singleton
```

If `scheduler` appears in the autoscaling map, the conditional merge broke and
you risk two schedulers running and double-firing jobs.

**Scheduler deployments are intentionally slow.** It runs `0/100`, so the old
task stops before the new one starts. Brief downtime is the price of never
running two schedulers at once. Do not "fix" this by raising
`maximum_percent`.

**Worker deployments run at `0/200`** — it can drop to zero healthy briefly
because a queue consumer has no user-facing impact. If your worker is not
idempotent on restart, raise `minimum_healthy_percent`.

---

### service-connect-tls

Service Connect with TLS issued from AWS Private CA.

**Required inputs:** `service_connect_namespace_arn`, `private_ca_arn`,
`service_connect_tls_role_arn`, `service_connect_log_group_name`, two security
groups, two task roles, plus the usual network and images.

**Service keys:** `api` (server, advertises TLS), `web` (client, advertises
nothing)

**Pre-flight — check the CA is usable:**

```bash
# private_ca_arn is an input to this example, not an output.
aws acm-pca describe-certificate-authority \
  --certificate-authority-arn <private-ca-arn> \
  --query 'CertificateAuthority.{Status:Status,Type:Type}'
```

`Status` must be `ACTIVE`. A `PENDING_CERTIFICATE` CA cannot issue, and the
tasks fail to start with no useful application-level error.

**Verify registration:**

```bash
aws servicediscovery list-services \
  --filters Name=NAMESPACE_ID,Values=<namespace-id> \
  --query 'Services[*].{Name:Name,Id:Id}' --output table
```

**When `web` cannot reach `api`, check in this order:**

1. **Port mapping is named.** `services[].port_name` must match a `name` on a
   task definition port mapping. An unnamed mapping registers nothing and
   produces DNS failures with nothing in the application logs.
   ```bash
   aws ecs describe-task-definition --task-definition "$(terraform output -json task_definition_arn | jq -r '.api')" \
     --query 'taskDefinition.containerDefinitions[0].portMappings'
   ```
2. **Sidecar logs.** This is where mesh failures actually surface — certificate
   issuance errors, upstream connection failures, timeouts.
   ```bash
   aws logs tail <service_connect_log_group_name> --follow --filter-pattern "service-connect"
   ```
3. **The TLS role can issue.** It needs `acm-pca:IssueCertificate` and
   `acm-pca:GetCertificate` on the CA, trusting `ecs.amazonaws.com`, plus
   `kms:GenerateDataKey` if a CMK is set.
4. **Security groups.** The `api` group must allow inbound from the `web` group
   on the api container port.

**Namespace type matters:** Service Connect needs an **HTTP** namespace, not a
DNS one.

---

### complete

Three tiers — `frontend`, `api`, `worker` — with Service Connect, a `CANARY`
deployment on the api, and autoscaling. Spelled out longhand.

**Required inputs:** the largest set of the eight; per-tier security groups,
execution roles, task roles and images, plus
`api_blue_target_group_arn` / `api_green_target_group_arn`,
`api_production_listener_rule_arn`, `service_connect_namespace_arn`,
`exec_log_group_name`, `alb_arn_suffix` and
`api_blue_target_group_arn_suffix`.

**Service keys:** `frontend`, `api`, `worker`

**Outputs:** `cluster_name`, `service_names`, `deployment_strategies`,
`task_definition_arns`

**The api canary is slow on purpose.** 10% for 10 minutes, then the rest, then
a 10 minute bake. Budget ~25 minutes per api deployment and do not interrupt it
mid-shift — an interrupted apply can leave the listener rule weighted
part-shifted.

If you must abort:

```bash
aws ecs update-service --cluster "$CLUSTER" --service <api-service> \
  --deployment-configuration '{"strategy":"ROLLING"}' \
  --force-new-deployment
```

**`alb_arn_suffix` and `api_blue_target_group_arn_suffix`** feed the
ALB-request-count autoscaling policy. They are the *suffix* portions
(`app/<lb-name>/<id>` and `targetgroup/<tg-name>/<id>`), not full ARNs. Getting
these wrong produces a policy that never triggers, silently.

---

### pattern5

A load-balanced edge tier with unexposed internal services — the frontend is
the only tier with a target group; `api` and `worker` are reachable only over
Service Connect.

**Required inputs:** as `complete`, minus the api blue/green target groups and
listener rule.

**Service keys:** `frontend`, `api`, `worker`

**Outputs:** `cluster_name`, `service_names`, `deployment_strategies`,
`task_definition_arns`

**Verify the internal tiers really are unexposed:**

```bash
# api and worker should return an empty loadBalancers list
aws ecs describe-services --cluster "$CLUSTER" \
  --services <api-service> <worker-service> \
  --query 'services[*].{Name:serviceName,LBs:loadBalancers}'
```

If either has a load balancer attached, the pattern's whole premise is broken.

---

## Cross-cutting troubleshooting

### Tasks will not start

```bash
# The failure reason is almost always in the service events.
aws ecs describe-services --cluster "$CLUSTER" --services <service> \
  --query 'services[0].events[0:5].message' --output text

# Then the stopped-task reason, which is more specific.
aws ecs list-tasks --cluster "$CLUSTER" --service-name <service> --desired-status STOPPED \
  --query 'taskArns[0]' --output text \
  | xargs -r -I{} aws ecs describe-tasks --cluster "$CLUSTER" --tasks {} \
      --query 'tasks[0].{Stopped:stoppedReason,Containers:containers[*].{Name:name,Reason:reason,Exit:exitCode}}'
```

| Symptom | Usual cause |
| --- | --- |
| `CannotPullContainerError` | No NAT/VPC endpoint route, or the execution role cannot read the ECR repo |
| `ResourceInitializationError` on secrets | Execution role missing `secretsmanager:GetSecretValue` / `ssm:GetParameters` |
| `unable to place a task` (EC2) | No instance with enough CPU/memory, host port conflict, ENI limit, or an unsatisfiable placement constraint |
| Task starts then stops immediately | Application crash — check the app log group, not ECS |
| Health checks fail | Target group path/port mismatch, or `health_check_grace_period_seconds` too short for a slow boot |

### Deployment stuck IN_PROGRESS

```bash
aws ecs describe-services --cluster "$CLUSTER" --services <service> \
  --query 'services[0].deployments[*].{Status:status,Rollout:rolloutState,Reason:rolloutStateReason}'
```

With the circuit breaker enabled (the default in most of these examples) ECS
gives up and rolls back on its own. Without it, a deployment can hang
indefinitely on failing health checks.

### ECS Exec into a running task

Enabled in `simple`, `ec2`, `blue-green-deployment`, `multiple-services` and
`service-connect-tls`.

```bash
TASK=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name <service> \
  --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster "$CLUSTER" --task "$TASK" \
  --container <container-name> --interactive --command "/bin/sh"
```

If it fails with a TargetNotConnected error, the task predates
`enable_execute_command`. Force a new deployment and retry.

---

## Rollback

### Terraform-driven services (the ECS controller)

Revert the image variable and apply. Terraform registers the previous task
definition content as a new revision and ECS rolls forward to it.

```bash
terraform apply -var="container_image=<previous-image>"
```

### Immediate rollback without Terraform

Faster during an incident, but leaves state drifted — reconcile afterwards.

```bash
# Find the previous revision
aws ecs list-task-definitions --family-prefix <family> --sort DESC \
  --query 'taskDefinitionArns[1]' --output text

aws ecs update-service --cluster "$CLUSTER" --service <service> \
  --task-definition <previous-task-def-arn>
```

Then bring Terraform back in line:

```bash
terraform plan   # expect a diff on task_definition — resolve by reverting the image var
```

### Traffic-shifting deployments

During the bake window, a named CloudWatch alarm entering ALARM rolls the
deployment back automatically. That is what `deployment_alarms` is for, and why
`bake_time_in_minutes` is worth setting generously.

To abort manually mid-shift, force a new deployment from the known-good task
definition (see above).

### External controller

Terraform cannot roll this back. Your deployment system shifts `scale` back to
the previous task set.

---

## Teardown

**Never run `terraform destroy` without inspecting the plan first.**

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan | less
terraform apply destroy.tfplan
```

Things that commonly block or complicate a destroy:

- **Services must scale to zero first.** The module sets `force_delete` only
  when you ask for it. If a destroy hangs on a service, scale it down:
  ```bash
  aws ecs update-service --cluster "$CLUSTER" --service <service> --desired-count 0
  ```
- **EC2 capacity providers cannot be removed while attached** to a cluster with
  running tasks. Scale services to zero, let the ASG drain, then destroy.
- **Capacity providers with managed termination protection** keep instances
  alive while tasks run. Draining is not instant.
- **Log groups, target groups, IAM roles and namespaces are inputs**, not
  module-managed. Destroy leaves them behind by design.
- **`skip_destroy` on a task definition** (off by default) keeps old revisions.

Never use `-auto-approve` on a destroy in a shared account.
