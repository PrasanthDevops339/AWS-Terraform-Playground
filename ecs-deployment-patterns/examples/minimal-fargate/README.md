# minimal-fargate

The smallest configuration that produces a running ECS service: one Fargate
task, no load balancer, the default `ROLLING` strategy on the `ECS` controller.

Start here, then read [`../fargate-all-deployment-types`](../fargate-all-deployment-types/)
for the rest of the deployment types.

## What it creates

- ECS cluster with Container Insights enabled
- one task definition and one Fargate service
- CloudWatch alarms for the service

## Prerequisites

Existing resources, passed in as variables:

- VPC and private subnets with a NAT or VPC endpoint route for image pulls
- a security group for the task ENIs
- task execution role and task role ARNs
- a CloudWatch log group at `/ecs/<cluster_name>/app`

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Notes

- Fargate requires both `cpu` and `memory` at the task level. The task is the
  billing unit, so there is nothing else to size against.
- Fargate always uses the `awsvpc` network mode, so `subnets` and
  `security_groups` are mandatory.
