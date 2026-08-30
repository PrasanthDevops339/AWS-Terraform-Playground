output "cluster_name" {
  description = "Created ECS cluster name"
  value       = module.ecs_service.cluster_name
}

output "service_names" {
  description = "Created ECS service names keyed by service key"
  value       = module.ecs_service.service_name
}

output "task_definition_arns" {
  description = "Task definition ARNs keyed by service key"
  value       = module.ecs_service.task_definition_arn
}
