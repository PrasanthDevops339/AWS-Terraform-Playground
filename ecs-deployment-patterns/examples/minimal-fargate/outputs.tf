output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "service_names" {
  description = "ECS service names keyed by container_config key"
  value       = module.ecs.service_name
}

output "deployment_summary" {
  description = "Resolved launch type and deployment shape per service"
  value       = module.ecs.service_deployment_summary
}
