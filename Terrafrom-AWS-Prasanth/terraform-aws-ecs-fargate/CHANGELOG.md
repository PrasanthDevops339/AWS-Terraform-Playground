# Changelog

## [Unreleased]

### Breaking

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
