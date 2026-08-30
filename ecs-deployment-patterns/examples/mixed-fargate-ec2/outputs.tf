output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "deployment_summary" {
  description = "Resolved launch type, network mode and deployment shape per service. Shows Fargate and EC2 side by side on one cluster"
  value       = module.ecs.service_deployment_summary
}

output "capacity_provider_names" {
  description = "EC2 capacity provider names created alongside the Fargate providers"
  value       = module.ecs.capacity_provider_names
}

output "service_names" {
  description = "ECS service names keyed by container_config key"
  value       = module.ecs.service_name
}
