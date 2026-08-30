output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_blue_green.cluster_name
}

output "service_name" {
  description = "ECS service names keyed by container_config key"
  value       = module.ecs_blue_green.service_name
}

output "deployment_summary" {
  description = "Resolved deployment shape. deployment_controller should read ECS and shifts_traffic should be true"
  value       = module.ecs_blue_green.service_deployment_summary
}

output "infrastructure_iam_role_arns" {
  description = "The ECS infrastructure role the module created to reweight the listener rule"
  value       = module.ecs_blue_green.infrastructure_iam_role_arns
}

output "alarm_names_for_rollback" {
  description = "Per-service alarm names, ready to feed back into rollback_alarm_names on a second apply"
  value       = module.ecs_blue_green.alarm_names_for_rollback
}
