output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_external.cluster_name
}

output "service_name" {
  description = "ECS service names keyed by container_config key. Pass this to your deployment system as the CreateTaskSet target"
  value       = module.ecs_external.service_name
}

output "task_definition_arn" {
  description = "Task definition ARN including revision, for referencing from a task set"
  value       = module.ecs_external.task_definition_arn
}

output "task_definition_arn_without_revision" {
  description = "Task definition ARN without the revision, useful when the external system resolves the latest itself"
  value       = module.ecs_external.task_definition_arn_without_revision
}

output "deployment_summary" {
  description = "Resolved deployment shape. deployment_controller should read EXTERNAL"
  value       = module.ecs_external.service_deployment_summary
}

output "task_set_id" {
  description = "ID of the bootstrap task set, or null when create_initial_task_set is false"
  value       = try(aws_ecs_task_set.initial[0].task_set_id, null)
}

output "task_set_stability_status" {
  description = "Whether the bootstrap task set reached steady state"
  value       = try(aws_ecs_task_set.initial[0].stability_status, null)
}
