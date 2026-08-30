# Complete Example

This example demonstrates a three-tier ECS Fargate application on one cluster.

Services:

- `frontend`: edge-facing web tier with a standard target group and rolling
  updates
- `api`: internal HTTP tier using Service Connect and ECS-native `CANARY`
  deployment
- `worker`: background tier with no target group and a
  `FARGATE`/`FARGATE_SPOT` mix

## What It Demonstrates

- shared cluster with multiple services from one `container_config` map
- cluster managed storage configuration
- cluster default capacity providers
- Service Connect namespace defaults
- named container port mappings
- ECS-native canary deployment with advanced target group wiring
- CPU, memory, ALB request count, and scheduled autoscaling
- per-service security group and IAM separation

## External Prerequisites

This example intentionally keeps platform dependencies outside the module. You
must provide:

- VPC ID and subnet IDs
- security group IDs for each tier
- execution role and task role ARNs for each tier
- Service Connect namespace ARN
- frontend target group ARN
- API blue target group ARN
- API green target group ARN
- API production listener rule ARN
- ECS ALB infrastructure role ARN for API traffic shifting
- CloudWatch log groups
- container images

## When To Use It

Use this example when you want a realistic starting point for:

- frontend plus internal API plus worker layouts
- ECS-native canary or other traffic-shifting deployments
- Service Connect between tiers
- mixed on-demand and Spot capacity

If you only need one service behind one target group, start with
[`examples/simple`](../simple/README.md).
