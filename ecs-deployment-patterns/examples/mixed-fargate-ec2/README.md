# mixed-fargate-ec2

One cluster, both launch types. This is the shape most platforms converge on:
each workload picks the capacity that suits it, rather than one cluster per
launch type.

| Service | Capacity | Why |
| --- | --- | --- |
| `api` | Fargate | Spiky and latency-sensitive; no instances worth managing |
| `gpu_inference` | EC2, `g5.xlarge` | Needs GPUs, which Fargate does not offer |
| `batch` | EC2 Spot, mixed instances | Interruption-tolerant, so cheapest capacity wins |
| `node_agent` | EC2, `DAEMON` | One agent per container instance |

## Notes

- `node_agent` covers the **EC2 instances only**. Fargate tasks have no host to
  place a daemon on, which is the practical reason a monitoring agent has to be
  a sidecar inside the Fargate task definition.
- `gpu_inference` uses the GPU ECS-optimized AMI and a task placement
  constraint (`attribute:ecs.instance-type =~ g5.*`) so the task cannot land on
  a non-GPU instance.
- `gpu_inference` deploys at `0/100` percentages: GPU capacity is scarce and
  expensive, so ECS frees a task before placing its replacement rather than
  requiring a spare instance.
- No cluster-wide `default_capacity_provider_strategy` is set. Every service
  names its own capacity, so nothing lands on Spot or GPU instances by accident.

## Prerequisites

Existing VPC, subnets, security group, IAM roles, blue/green `ip` target groups
and a listener rule, plus images for the inference and batch workloads.

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

terraform output deployment_summary
```
