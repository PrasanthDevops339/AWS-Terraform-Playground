# Simple Example

This example shows the thinnest supported consumer of the module:

- one ECS cluster
- one ECS Fargate service
- one external target group
- one synthesized task definition

## What It Demonstrates

- minimal `container_config`
- named `port_mappings`
- external target group attachment
- `enable_execute_command`
- `enable_ecs_managed_tags`
- `health_check_grace_period_seconds`

## What You Must Provide

This example does not create surrounding infrastructure. Pass in:

- VPC ID
- subnet IDs
- service security group ID
- task execution role ARN
- task role ARN
- CloudWatch log group name
- target group ARN
- container image

## When To Use It

Use this example when:

- you want a single load-balanced service
- you need a clean starting point
- you do not need Service Connect or traffic-shifting deployments yet

If you need a real multi-tier shape, use
[`examples/complete`](../complete/README.md) instead.
