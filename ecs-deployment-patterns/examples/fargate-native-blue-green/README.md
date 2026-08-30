# fargate-native-blue-green

Blue/green, linear and canary deployments **without CodeDeploy**, using the
ECS-native deployment strategies.

This is the self-contained example: it builds the load balancer, both target
groups and both listener rules alongside the service, so the whole
traffic-shifting path reads in one file. The other examples take that wiring as
input.

## What "no CodeDeploy" actually means

There is no `aws_codedeploy_app`, no `aws_codedeploy_deployment_group`, no
AppSpec file and no CodeDeploy service role. ECS performs the deployment
itself, driven entirely by the service definition:

```hcl
deployment_configuration = {
  strategy             = "BLUE_GREEN"
  bake_time_in_minutes = 5
}
```

Swap `BLUE_GREEN` for `LINEAR` or `CANARY` and nothing else in this example
changes:

```hcl
# 20% of traffic every 3 minutes
deployment_configuration = {
  strategy             = "LINEAR"
  linear_configuration = { step_percent = 20, step_bake_time_in_minutes = 3 }
}

# 10% canary held for 15 minutes, then the rest
deployment_configuration = {
  strategy             = "CANARY"
  canary_configuration = { canary_percent = 10, canary_bake_time_in_minutes = 15 }
}
```

## The five moving parts

1. **Two target groups**, `blue` and `green`, both `target_type = "ip"`.
   Terraform creates them but attaches nothing — ECS registers and deregisters
   task IPs itself. Adding an `aws_lb_target_group_attachment` here would fight
   ECS.
2. **A production listener rule** that weighted-forwards across *both* target
   groups, starting at 100/0. This is the rule ECS rewrites.
3. **A test listener rule** pointing at green, so you can smoke-test the new
   version on port 8080 before it takes production traffic. Optional.
4. **`deployment_configuration.strategy`** on the service.
5. **An ECS infrastructure IAM role** that ECS assumes to reweight rule 2. The
   module creates this for you — `advanced_configuration.role_arn` is required
   by the AWS provider, so there is nothing useful for you to decide about it.

What ECS then does on each deployment: stand up a green task set, register it
in the green target group, wait for health checks, bake, reweight the
production rule to 0/100, bake again, tear down blue.

## Two things that bite people

**`production_listener_rule` is a listener RULE ARN, not a listener ARN.** It
looks like `...:listener-rule/app/<lb>/<id>/<listener>/<rule>`. Passing a
listener ARN fails at apply, not at plan, which is an expensive way to find
out.

**The production rule's weights drift, by design.** A completed blue/green
deployment leaves green at 100 and blue at 0, and the two swap roles again on
the next release. Without `ignore_changes`, every plan after a deployment shows
drift and tries to shove traffic back onto the target group that is no longer
live:

```hcl
resource "aws_lb_listener_rule" "production" {
  # ...
  lifecycle {
    ignore_changes = [action]
  }
}
```

The upstream `terraform-aws-modules/alb` module does **not** do this for you,
so if you build the ALB with that module you have to handle the drift yourself.

## Prerequisites

- VPC with public subnets (for the ALB) and private subnets (for the tasks)
- task execution role and task role ARNs
- a CloudWatch log group at `/ecs/<name_prefix>/app`

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan

# deployment_controller should read "ECS", not "CODE_DEPLOY"
terraform output deployment_summary
```

To trigger a deployment, change the image and apply. Watch it shift:

```bash
aws ecs describe-services --cluster <cluster> --services <service> \
  --query 'services[0].deployments[*].{Status:status,Rollout:rolloutState,TaskDef:taskDefinition}' \
  --output table
```

## Why there is no CodeDeploy option

CodeDeploy support was removed from the module. The ECS-native strategies cover
blue/green, linear and canary, and `lifecycle_hooks` covers most of what people
used AppSpec `BeforeAllowTraffic` / `AfterAllowTraffic` hooks for.

What you give up: CodeDeploy's manual approval gate (`STOP_DEPLOYMENT` with a
wait time) has no direct native equivalent. If you need a human to click
approve mid-deployment, gate it in your pipeline before the apply, or use a
`lifecycle_hook` Lambda that blocks until approved.

Passing `deployment_controller.type = "CODE_DEPLOY"` now fails validation with
a message pointing here, rather than silently creating no service.
