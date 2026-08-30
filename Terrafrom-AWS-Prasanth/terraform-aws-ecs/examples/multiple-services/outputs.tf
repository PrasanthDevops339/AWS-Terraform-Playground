output "cluster_name" {
  description = "Name of the shared ECS cluster"
  value       = module.ecs_multi.cluster_name
}

output "service_name" {
  description = "ECS service names keyed by service key"
  value       = module.ecs_multi.service_name
}

output "deployment_summary" {
  description = "Resolved deployment shape per service. Confirms web is BLUE_GREEN while the rest are ROLLING"
  value       = module.ecs_multi.service_deployment_summary
}

output "autoscaling_target_resource_id" {
  description = "Application Auto Scaling resource IDs. The scheduler is deliberately absent - a singleton must stay a singleton"
  value       = module.ecs_multi.autoscaling_target_resource_id
}

output "task_definition_arn" {
  description = "Task definition ARNs keyed by service key"
  value       = module.ecs_multi.task_definition_arn
}

output "alarm_names_for_rollback" {
  description = "Per-service alarm names, ready to feed into a deployment_configuration.alarms block"
  value       = module.ecs_multi.alarm_names_for_rollback
}
