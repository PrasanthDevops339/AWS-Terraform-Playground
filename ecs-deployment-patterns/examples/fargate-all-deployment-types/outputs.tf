output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "deployment_summary" {
  description = "Resolved launch type and deployment shape per service. The quickest check that each service got the shape intended"
  value       = module.ecs.service_deployment_summary
}

output "service_names" {
  description = "ECS service names keyed by container_config key"
  value       = module.ecs.service_name
}

output "alarm_names_for_rollback" {
  description = "Per-service alarm names, ready to feed back into rollback_alarm_names on a second apply"
  value       = module.ecs.alarm_names_for_rollback
}

output "infrastructure_iam_role_arns" {
  description = "ECS infrastructure role per service - the role ECS assumes to reweight listener rules. Traffic shifting is native, so no CodeDeploy service role exists"
  value       = module.ecs.infrastructure_iam_role_arns
}
