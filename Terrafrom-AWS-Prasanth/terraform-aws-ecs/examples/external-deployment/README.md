# external-deployment

An ECS service using the `EXTERNAL` deployment controller, where a third-party
system owns the rollout.

## What "external" means

ECS creates only the service shell. Everything about the running tasks — which
task definition, how many, which subnets, which target group — lives on **task
sets** created through the `CreateTaskSet` API.

That is why the `service` block is nearly empty. Setting `task_definition`,
`network_configuration` or `load_balancer` on an EXTERNAL service is rejected
by ECS, and the module omits them for you.

| Lives on the service | Lives on the task set |
| --- | --- |
| Deployment controller type | Task definition |
| Total desired count | Network configuration |
| Tags, managed tags | Load balancer attachment |
| Autoscaling boundaries | Scale (percent of desired count) |
| | Launch type / capacity provider |

## The bootstrap task set

This example includes one [`aws_ecs_task_set`](main.tf) so it produces
something that actually serves traffic, and so the shape of a task set is
visible.

In a real setup you would either drop it and let the deployment system create
every task set, or keep it as a bootstrap and let the pipeline manage the rest.
**Do not manage the same task set from both places.** Set
`create_initial_task_set = false` to omit it.

Note the `scale` block is a **percentage** of the service's desired count. An
externally-driven blue/green cutover moves the old task set from 100 to 0 while
raising the new one from 0 to 100.

## Autoscaling still works

Application Auto Scaling adjusts the *service's* desired count; the external
system decides how that is distributed across task sets. The module registers
the scaling target for EXTERNAL services the same as for ECS-controller ones.

## When to use this

- Spinnaker, Argo Rollouts, Harness or an in-house release tool owns deploys
- you need a deployment model ECS-native strategies do not express, such as
  shifting traffic on a signal Terraform cannot see

If you only need blue/green, linear or canary, use the ECS controller instead —
see [`../blue-green-deployment`](../blue-green-deployment/). It is far less
machinery.

## Prerequisites

- VPC, private subnets, and a task security group
- task execution role and task role ARNs
- a CloudWatch log group
- optionally a target group (`target_type = "ip"`) for the task set

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Should read EXTERNAL
terraform output deployment_summary

# List task sets your deployment system can now act on
aws ecs describe-services --cluster <cluster> --services <service> \
  --query 'services[0].taskSets[*].{Id:id,Status:status,Scale:scale,Stability:stabilityStatus}'
```
