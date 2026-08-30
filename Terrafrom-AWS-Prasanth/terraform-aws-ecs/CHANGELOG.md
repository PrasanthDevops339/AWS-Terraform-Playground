# Changelog

## [Unreleased]

### Breaking

- **Removed CodeDeploy support entirely.** `aws_codedeploy_app`,
  `aws_codedeploy_deployment_group`, the CodeDeploy service role and the
  `aws_ecs_service.codedeploy` resource are gone, along with the
  `codedeploy_app_name`, `codedeploy_deployment_group_name` and
  `codedeploy_role_arns` outputs. Blue/green, linear and canary are performed
  natively by ECS via `deployment_configuration.strategy`, which needs no
  CodeDeploy application, deployment group, AppSpec or service role.
  `deployment_controller.type` now accepts only `ECS` and `EXTERNAL`, and a
  `CODE_DEPLOY` value fails validation rather than silently creating no
  service.

  **Migration:** a service previously on the CodeDeploy controller should move
  to `deployment_configuration = { strategy = "BLUE_GREEN" }` plus
  `alternate_target_group_arn` and `production_listener_rule` on its target
  group entry. The nearest equivalents for CodeDeploy deployment configs are
  `LINEAR` (`linear_configuration`) and `CANARY` (`canary_configuration`).
  There is no native equivalent of CodeDeploy's manual approval gate; gate it
  in the pipeline or use a `lifecycle_hook` Lambda instead.

  **If you have existing state**, the CodeDeploy resources and the
  `aws_ecs_service.codedeploy` instances will be planned for destruction.
  Review `terraform plan -destroy`-level output carefully, and use `removed`
  blocks (Terraform 1.7+) to drop them from state without deleting the running
  service if that is what you want.
- `deployment.tf` was renamed to `ecs-service-external.tf`; it now holds only
  the EXTERNAL deployment controller.
- `examples/complet-parten5` was renamed to `examples/pattern5`, fixing the
  directory name typo. README references updated.
- Example provider floors raised from `>= 6.34.0` to `~> 6.62`, matching the
  module. The old floor would let Terraform select a provider too old for the
  `LINEAR` and `CANARY` strategies the examples use.
- Renamed the module directory from `terraform-aws-ecs-fargate` to
  `terraform-aws-ecs`. It is no longer Fargate-only. Update `source` paths.
- Raised the AWS provider floor to `~> 6.62`, the version the module is
  schema-verified against. Required by the ECS-native `LINEAR` and `CANARY`
  strategies and by `advanced_configuration.test_listener_rule`.
- ECS-controller services no longer ignore `task_definition` changes by
  default. Terraform now performs the deployment, which is what the module
  always claimed to do. Set `service.ignore_task_definition_changes = true` to
  restore the old behaviour for a service whose image is rolled by an external
  pipeline.
- Service outputs (`service_id`, `service_name`, `service_cluster`,
  `service_desired_count`, `service_iam_role`) are now keyed by the plain
  `container_config` key for every controller. The `_codedeploy` and
  `_external` key suffixes are gone.

### Fixed

- The `alarms` block was nested inside `deployment_configuration`, where it is
  not a valid block. It is a top-level block on `aws_ecs_service`, and the
  module failed `terraform validate` because of this.
- `data.aws_region.current.name` is deprecated in AWS provider 6.x and is now
  `.region`.
- Two CodeDeploy deployment group bugs (a `target_group_info` block where ECS
  blue/green requires `target_group_pair_info`, and an invalid
  `green_fleet_provisioning_option`) are moot: CodeDeploy has been removed.
- The `RunningTaskCount` alarm published to `ECS/ContainerInsights` regardless
  of the cluster setting, so it sat permanently in ALARM on missing data when
  Container Insights was disabled. It is now only created when Insights is on.
- Services referenced `aws_ecs_cluster.main[0]` unconditionally, so
  `create_cluster = false` could not work. Added `existing_cluster_arn`, with a
  validation that requires it in that case.
- IAM policy ARNs were hardcoded to the `aws` partition and now use
  `data.aws_partition`, so the module works in GovCloud and China regions.
- CloudWatch alarms and autoscaling targets only resolved service names for the
  ECS controller, so external services silently got neither.

### Added

- **EC2 launch type.** `ec2_capacity_providers` builds launch template ->
  Auto Scaling group -> ECS capacity provider, with managed scaling, managed
  draining, scale-in protection, IMDSv2, an instance role and instance security
  groups. Supports both single-instance-type and mixed-instances/Spot ASGs.
- `launch_type_default` and per-service `service.launch_type`
  (`FARGATE` / `EC2` / `EXTERNAL`).
- Per-service `task_definition.network_mode` (`awsvpc`, `bridge`, `host`,
  `none`), defaulting to `awsvpc` on Fargate and `bridge` on EC2. The
  `network_configuration` block is now only emitted for `awsvpc`.
- `DAEMON` scheduling strategy, with `desired_count` and
  `deployment_maximum_percent` suppressed as the API requires.
- `advanced_configuration.test_listener_rule` for validating green before a
  cutover.
- Service `volume_configuration` for ECS-managed EBS volumes, and
  `vpc_lattice_configurations`.
- EC2-only task definition surface: `docker_volumes`, `bind_mount_volumes` with
  `host_path`, `pid_mode`, `ipc_mode`, and task `placement_constraints`.
- `availability_zone_rebalancing`, `force_delete`, `track_latest` and
  `skip_destroy`.
- **ECS infrastructure IAM role, created automatically.** ECS-native
  `BLUE_GREEN` / `LINEAR` / `CANARY` require
  `advanced_configuration.role_arn`, which the provider marks required, so a
  traffic-shifting service previously could not plan without the caller
  supplying `ecs_alb_service_role_arn` by hand. The module now creates one per
  service that needs it, attaching
  `AmazonECSInfrastructureRolePolicyForLoadBalancers`, plus the volumes and VPC
  Lattice policies when those features are used. Controlled by
  `create_infrastructure_iam_role` (default true) and
  `infrastructure_iam_role_permissions_boundary`; an explicit
  `ecs_alb_service_role_arn` still wins. Matches the behaviour of
  `terraform-aws-modules/terraform-aws-ecs`.
- `infrastructure_iam_role_arns` output.
- `service_deployment_summary` output: the resolved launch type, network mode,
  scheduling strategy and deployment controller per service.
- `alarm_names_for_rollback` output, ready to feed back into
  `deployment_configuration.alarms.alarm_names`.
- EC2 capacity outputs: `capacity_provider_names`, `capacity_provider_arns`,
  `container_instance_autoscaling_group_names`, `container_instance_role_arn`,
  `container_instance_security_group_ids`.
- `examples/ec2`: the EC2 launch type counterpart to `examples/simple`, showing
  an Auto Scaling group backed capacity provider, bridge networking, ephemeral
  host ports and EC2 placement strategies.
- Built out the four example directories that had been scaffolded and left
  empty. Git does not track empty directories, so they were invisible in
  `git status`:
  - `examples/blue-green-deployment`: ECS-native `BLUE_GREEN`, with the
    `LINEAR` and `CANARY` variants documented alongside.
  - `examples/external-deployment`: the `EXTERNAL` controller plus a real
    `aws_ecs_task_set`, showing what lives on the service versus the task set.
  - `examples/multiple-services`: four services assembled from a shared base
    via `merge()`, including a singleton scheduler that opts out of autoscaling.
  - `examples/service-connect-tls`: Service Connect with TLS issued from AWS
    Private CA, covering both the advertising server and the client-only side.
- `examples/complete` no longer requires `api_ecs_alb_service_role_arn`; it
  defaults to null now that the module creates the infrastructure role.
- `tests/deployment_matrix.tftest.hcl`: a mocked-provider test suite covering
  the launch-type and deployment-type matrix. No credentials, no cost.

### Breaking (previous)

- Raised the module floor to Terraform `>= 1.5.7`.
- Raised the AWS provider floor to `>= 6.34.0`.
- Removed target group creation from the ECS module. Target groups must be
  created externally and passed in through service target group mappings.

### Added

- Cluster managed storage configuration support.
- Service-level support for `enable_ecs_managed_tags`.
- Service-level support for `health_check_grace_period_seconds`.
- Synthesized task definition support for `environment`.
- Synthesized task definition support for named `port_mappings`.
- Synthesized task definition support for `mount_points`.
- Synthesized task definition support for `firelens_configuration`.
- Dedicated user guide for multi-tier layouts and deployment strategies.

### Changed

- Refactored task definition rendering so `container_definitions` are composed
  in locals, which makes the file easier to read and easier for IDE language
  servers to parse.
- Updated the maintained examples to `examples/simple` and
  `examples/complete`.
- Rewrote the module Markdown docs to match the current module surface and
  example set.
- Re-centered the main documentation on ECS-native deployment strategies for
  Fargate.

### Fixed

- Fixed `max-buffer-size` access in synthesized task definition log
  configuration so dashed keys no longer break Terraform parsing.
- Fixed the legacy CodeDeploy deployment group to reference the correct ECS
  service resource.
