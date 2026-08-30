output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_service_connect.cluster_name
}

output "service_name" {
  description = "ECS service names keyed by service key"
  value       = module.ecs_service_connect.service_name
}

output "deployment_summary" {
  description = "Resolved deployment shape per service"
  value       = module.ecs_service_connect.service_deployment_summary
}

output "api_endpoint" {
  description = "The address web resolves over the mesh. Traffic is encrypted by the sidecar, not the application"
  value       = "http://api:${var.api_container_port}"
}

output "task_definition_arn" {
  description = "Task definition ARNs keyed by service key"
  value       = module.ecs_service_connect.task_definition_arn
}
