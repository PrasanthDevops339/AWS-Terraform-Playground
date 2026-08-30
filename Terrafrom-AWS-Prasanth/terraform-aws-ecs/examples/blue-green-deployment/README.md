# blue-green-deployment

One service using the ECS-native `BLUE_GREEN` deployment strategy.

ECS performs the deployment itself. There is no CodeDeploy application,
deployment group, AppSpec file or CodeDeploy service role.

## What ECS does on each deployment

1. Stands up a green task set and registers it in the alternate target group.
2. Waits for the green targets to pass health checks.
3. Optionally routes test traffic to green via `test_listener_rule`.
4. Reweights the production listener rule from blue to green.
5. Bakes for `bake_time_in_minutes` — an alarm firing here still rolls back.
6. Tears down blue.

## The wiring it needs

```hcl
deployment_configuration = {
  strategy             = "BLUE_GREEN"
  bake_time_in_minutes = 10
}

target_groups = [{
  target_group_arn           = var.blue_target_group_arn
  alternate_target_group_arn = var.green_target_group_arn
  production_listener_rule   = var.production_listener_rule_arn
  test_listener_rule         = var.test_listener_rule_arn  # optional
  container_name             = "app"
  container_port             = 8080
}]
```

The IAM role ECS assumes to reweight the rule is created by the module, so it
is not an input here.

## Switching to LINEAR or CANARY

Same target groups, same role, only the strategy block changes:

```hcl
# 20% of traffic every 3 minutes
deployment_configuration = {
  strategy             = "LINEAR"
  bake_time_in_minutes = 5
  linear_configuration = {
    step_percent              = 20
    step_bake_time_in_minutes = 3
  }
}

# 10% canary held 15 minutes, then the rest
deployment_configuration = {
  strategy             = "CANARY"
  bake_time_in_minutes = 5
  canary_configuration = {
    canary_percent              = 10
    canary_bake_time_in_minutes = 15
  }
}
```

## Prerequisites

- VPC, private subnets, and a task security group
- blue and green target groups, both `target_type = "ip"`
- an ALB listener plus the listener **rule** ARN ECS reweights
- task execution role and task role ARNs
- a CloudWatch log group

## Two things that bite people

**`production_listener_rule` is a listener RULE ARN, not a listener ARN.** It
looks like `...:listener-rule/app/<lb>/<id>/<listener>/<rule>`. Passing a
listener ARN fails at apply, not at plan.

**The rule's weights drift by design.** A completed deployment leaves green at
100 and blue at 0, and they swap again next release. If you manage the listener
rule in Terraform, guard it:

```hcl
resource "aws_lb_listener_rule" "production" {
  lifecycle {
    ignore_changes = [action]
  }
}
```

For a self-contained version that builds the ALB, target groups and rules
alongside the service, see
[`ecs-deployment-patterns/examples/fargate-native-blue-green`](../../../../ecs-deployment-patterns/examples/fargate-native-blue-green/).

## Alarm-based rollback is a two-pass apply

The alarms must exist before a deployment can reference them. Apply once with
`rollback_alarm_names = []`, then feed back the `alarm_names_for_rollback`
output.
