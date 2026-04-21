output "cluster_name" {
  description = "Created ECS cluster name"
  value       = module.three_tier_app.cluster_name
}

output "service_names" {
  description = "Created ECS service names keyed by tier"
  value       = module.three_tier_app.service_name
}

output "deployment_strategies" {
  description = "Effective deployment strategy for each ECS service"
  value       = module.three_tier_app.service_deployment_strategy
}

output "task_definition_arns" {
  description = "Task definition ARNs keyed by tier"
  value       = module.three_tier_app.task_definition_arn
}
