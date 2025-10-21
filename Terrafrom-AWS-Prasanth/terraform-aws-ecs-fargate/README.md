# terraform-aws-ecs-fargate

Opinionated ECS on Fargate module that attaches services to ALB/NLB Target Groups created outside this module (e.g., by your ALB module). As of this version, this module no longer creates Target Groups.

## Breaking change: TGs must be supplied

- This module no longer creates Target Groups. Provide `target_group_arn` values for each entry in `var.target_groups` from your external ALB module.
- Validation: If `load_balanced = true`, every entry in `target_groups` must include a non-empty `target_group_arn`. This fails fast during `terraform validate` to avoid confusing errors at apply time.

## Variable: `target_groups`

Input shape depends on your use case:

### Variable summary

| Name           | Description                                                                                                                                                                                                                               | Type       | Default | Required         |
|----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------|---------|------------------|
| `target_groups` | Target group config to associate with the ECS service. Case 1: provide `target_group_arn` for each entry (reusing ALB TGs). Case 2: provide `target_group_name` (module creates TG). Include `container_name`/`container_port` to map correctly. | list(any)  | `[]`    | No (conditional) |

Note: When `load_balanced = true` and `create_target_groups = false`, each entry must include a non-empty `target_group_arn`.

- Reusing external TGs (Case 1):
	- Each entry must include `target_group_arn`
	- You should also specify `container_name` and `container_port` so the ECS service can map the correct container/port

- Creating TGs here (Case 2):
	- Provide `target_group_name` (required)
	- Optional: `container_port`, `deregistration_delay`
	- Also specify `container_name` if your task container name doesn’t match this module’s default naming convention

Common optional health check settings are provided via `var.health_check`.

## Examples

### Example — Use ALB module TGs

```hcl
module "app_container" {
	source              = "../../"         # path to this module
	vpc_id              = data.aws_vpc.main.id
	cluster_name        = "ecs-cluster-example"
	create_cluster      = true

	# Map ECS service to TGs created by an external ALB module
	target_groups = [
		{
			target_group_arn = module.alb.target_groups["ex-ip"].id
			container_name   = "first-complete"
			container_port   = 80
		}
	]

	container_config = {
		"first-app" = {
			container_name = "first-complete"
			service = {
				desired_count        = 1
				container_port       = 80
				security_groups      = [module.ecs_sg.security_group_id]
				subnets              = [element(data.aws_subnets.app_subnets.ids, 0)]
				enable_execute_command = true
				force_new_deployment = true
			}
			task_definition = {
				cpu                 = 2048
				memory              = 4096
				image               = "${module.ecr.repository_url}:latest"
				execution_role_arn  = module.iam_role.iam_role_arn
				task_role_arn       = module.iam_role.iam_role_arn
				host_port           = 80
				container_port      = 80
			}
		}
	}
}
```

### Removing TG creation

Older examples showing TG creation inside this module have been removed. Ensure your ALB module creates TGs and exposes their ARNs for wiring here.

## Variable reference (excerpt)

- `load_balanced` (bool, default `true`): Whether to attach the service to LB target groups
- `target_groups` (list(any), default `[]`):
	- Each entry must include `target_group_arn` and should specify `container_name`, `container_port`
- `task_container_port` (number, default `80`): Default container port
// Removed: `task_container_protocol` and `health_check` as Target Groups are not created here

## Notes

- Fargate requires `awsvpc` networking; ensure `subnets` and `security_groups` are provided per service
- Target Groups use `target_type = "ip"`
- Ensure `container_name` in `target_groups` matches the container name in your task definition (or use the module’s default naming convention if aligned)
- You still need an ALB/NLB, listeners, and listener rules to route traffic to the TGs

