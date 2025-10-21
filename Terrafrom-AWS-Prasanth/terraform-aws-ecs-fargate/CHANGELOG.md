# Changelog

## [Unreleased]

### Breaking
- Removed Target Group creation from the ECS module. Target Groups must now be created externally (e.g., via an ALB module) and passed in via `target_group_arn`.
- Removed variables related to TG creation and configuration: `create_target_groups`, `task_container_protocol`, and `health_check`.

### Changed
- Tightened `target_groups` validation: when `load_balanced=true`, each entry must include a non-empty `target_group_arn`.
- Updated README and `examples/complete` to reflect the new requirement and usage.

