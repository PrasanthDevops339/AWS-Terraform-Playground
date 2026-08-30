output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "deployment_summary" {
  description = "Resolved launch type, network mode and deployment shape per service"
  value       = module.ecs.service_deployment_summary
}

output "capacity_provider_names" {
  description = "EC2 capacity provider names, as referenced by each service capacity_provider_strategy"
  value       = module.ecs.capacity_provider_names
}

output "container_instance_autoscaling_group_names" {
  description = "Auto Scaling groups backing the capacity providers"
  value       = module.ecs.container_instance_autoscaling_group_names
}

output "container_instance_role_arn" {
  description = "IAM role the container instances run as"
  value       = module.ecs.container_instance_role_arn
}

output "container_instance_security_group_ids" {
  description = "Security groups created for the container instances"
  value       = module.ecs.container_instance_security_group_ids
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
