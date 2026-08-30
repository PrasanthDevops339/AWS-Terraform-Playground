# multiple-services

Four services on one cluster, built from a shared base rather than spelled out
longhand.

Where [`../complete`](../complete/) writes three tiers out in full, this one
shows the DRY shape: a `task_base` and `service_base` in locals, merged with a
per-service override map. The pattern earns its keep once you pass three or
four services.

Every service still gets its own task definition, IAM wiring, autoscaling
policies, alarms and deployment configuration. The merge only removes the
copy-paste.

## The four services

| Service | Load balanced | Deployment | Scales on | Why it differs |
| --- | --- | --- | --- | --- |
| `web` | yes, blue/green | `BLUE_GREEN`, 10 min bake | CPU 55% | Public tier, so it gets the safest strategy |
| `api` | yes | `ROLLING` 100/200 | CPU 60% | Internal, so in-place is fine |
| `worker` | no | `ROLLING` 0/200 | Memory 70% | Queue consumer: can drop to zero healthy briefly, and is memory-bound |
| `scheduler` | no | `ROLLING` 0/100 | not at all | Singleton — a second task would double-fire jobs |

The interesting parts are the deliberate differences:

- **`worker` uses `minimum_healthy_percent = 0`.** A queue consumer can go to
  zero briefly with no user impact, which makes deployments cheaper and faster.
- **`scheduler` uses `0/100`.** This guarantees the old task stops *before* the
  new one starts, so two schedulers never run at once.
- **`scheduler` has no `autoscaling` block at all.** The assembly step omits
  the key entirely rather than passing a disabled one, so no scaling target is
  registered. A singleton must stay a singleton.
- **`worker` disables the CPU policy** and enables the memory one, because
  queue consumers are usually memory-bound.

## The assembly

```hcl
container_config = {
  for name, svc in local.services : name => merge(
    {
      container_name  = name
      task_definition = merge(local.task_base, { image = svc.image, ... })
      service         = merge(local.service_base, { ... }, svc.service_extra)
      alarms          = { enabled = true, ... }
    },
    svc.autoscaling == null ? {} : { autoscaling = svc.autoscaling },
  )
}
```

The conditional merge on the last line is what lets a service opt out of
autoscaling entirely rather than passing a disabled block.

## Prerequisites

- VPC and private subnets
- **three** security groups — web, api, and one shared by worker/scheduler.
  Separate groups are what keep the tiers isolated.
- blue and green target groups for `web` (`target_type = "ip"`), plus the
  listener rule ARN ECS reweights
- one target group for `api`
- task execution role and task role ARNs
- CloudWatch log groups under `/ecs/<cluster_name>/`

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Confirms web is BLUE_GREEN while the rest are ROLLING
terraform output deployment_summary

# The scheduler should be absent from this map
terraform output autoscaling_target_resource_id
```

## Note on the shared task role

Both `task_role_arn` and `execution_role_arn` are shared across all four
services here to keep the example readable. In production, split the task role
per service — the worker and the web tier rarely need the same permissions,
and a shared role is the easiest way to grant more than you meant to.
