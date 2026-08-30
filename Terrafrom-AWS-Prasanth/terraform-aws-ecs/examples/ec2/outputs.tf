output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_ec2.cluster_name
}

output "capacity_provider_names" {
  description = "EC2 capacity provider names, as referenced by the service capacity_provider_strategy"
  value       = module.ecs_ec2.capacity_provider_names
}

output "container_instance_autoscaling_group_names" {
  description = "Auto Scaling group backing the capacity provider"
  value       = module.ecs_ec2.container_instance_autoscaling_group_names
}

output "container_instance_role_arn" {
  description = "IAM role the container instances run as"
  value       = module.ecs_ec2.container_instance_role_arn
}

output "container_instance_security_group_ids" {
  description = "Security group created for the container instances"
  value       = module.ecs_ec2.container_instance_security_group_ids
}

output "service_name" {
  description = "ECS service names keyed by container_config key"
  value       = module.ecs_ec2.service_name
}

output "deployment_summary" {
  description = "Resolved launch type, network mode and deployment shape per service"
  value       = module.ecs_ec2.service_deployment_summary
}
