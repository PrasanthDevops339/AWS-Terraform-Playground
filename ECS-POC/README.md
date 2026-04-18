# ECS-POC

Standalone local ECS Fargate proof of concept.

This directory is a reference implementation for a local Fargate-oriented ECS
POC. It is useful for trying ideas quickly, but it is not kept in exact lockstep
with the internal module at
`Terrafrom-AWS-Prasanth/terraform-aws-ecs-fargate`.

## Scope

The POC is focused on:

- ECS Fargate only
- one application stack for experimentation
- multi-tier service patterns
- modern ECS features that are practical for local iteration

It is not intended to be a full mirror of the upstream
`terraform-aws-modules/terraform-aws-ecs` surface.

## Current Position In This Repository

Use the POC when you want:

- a local sandbox for ECS Fargate ideas
- a standalone stack to test wiring and patterns
- a place to validate assumptions before folding them into the internal module

Use the internal module when you want:

- reusable module inputs
- consistent multi-service structure
- maintained examples and module-level documentation

## Version Requirements

- Terraform `>= 1.5.7`
- AWS provider `>= 6.34.0`

## What To Expect

The POC may demonstrate or experiment with:

- ECS-native deployment strategies
- Service Connect
- autoscaling
- ECS Exec
- EFS integration
- runtime platform settings
- CloudWatch alarms and logging patterns

Because it is a POC, documentation here is descriptive rather than a strict
public module contract.

## Suggested Workflow

1. Prototype the service shape in this POC.
2. Validate AWS-side prerequisites such as IAM, networking, and listener rules.
3. Move stable patterns into the internal module and its maintained examples.

## Related Docs

- [`RUNBOOK.md`](./RUNBOOK.md): operational commands and rollback guidance
- [Internal module README](../Terrafrom-AWS-Prasanth/terraform-aws-ecs-fargate/README.md)
- [Internal module user guide](../Terrafrom-AWS-Prasanth/terraform-aws-ecs-fargate/USER_GUIDE.md)
