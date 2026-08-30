output "cluster_id" {
  description = "Id of the AWS ECS cluster"
  value       = local.cluster_id
}

output "cluster_arn" {
  description = "ARN that identifies the cluster."
  value       = var.create_cluster ? aws_ecs_cluster.main[0].arn : null
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = local.cluster_name_full
}

output "service_id" {
  description = "ARN that identifies the ECS services"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.id },
    { for k, v in aws_ecs_service.main_unmanaged_td : k => v.id },
    { for k, v in aws_ecs_service.external : k => v.id }
  )
}

output "service_name" {
  description = "Name of the ECS services"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.name },
    { for k, v in aws_ecs_service.main_unmanaged_td : k => v.name },
    { for k, v in aws_ecs_service.external : k => v.name }
  )
}

output "service_cluster" {
  description = "Cluster which the service is running on"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.cluster },
    { for k, v in aws_ecs_service.main_unmanaged_td : k => v.cluster },
    { for k, v in aws_ecs_service.external : k => v.cluster }
  )
}

output "service_desired_count" {
  description = "Number of instances of the task definition"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.desired_count },
    { for k, v in aws_ecs_service.main_unmanaged_td : k => v.desired_count },
    { for k, v in aws_ecs_service.external : k => v.desired_count }
  )
}

output "service_iam_role" {
  description = "ARN of the IAM role associated with the service"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.iam_role },
    { for k, v in aws_ecs_service.main_unmanaged_td : k => v.iam_role },
    { for k, v in aws_ecs_service.external : k => v.iam_role }
  )
}

output "cpu_scaling_policy" {
  description = "Attributes of cpu scaling policy"
  value       = aws_appautoscaling_policy.cpu_scaling
}

output "memory_scaling_policy" {
  description = "Attributes of memory scaling policy"
  value       = aws_appautoscaling_policy.memory_scaling
}

output "step_scaling_policy" {
  description = "Attributes of step scaling policy"
  value       = aws_appautoscaling_policy.step_policy
}

output "task_definition_arn" {
  description = "Full ARN of the Task Definition (including both family and revision)."
  value       = { for k, v in aws_ecs_task_definition.main : k => v.arn }
}

output "task_definition_arn_without_revision" {
  description = "ARN of the Task Definition with the trailing revision removed. This may be useful for updates."
  value       = { for k, v in aws_ecs_task_definition.main : k => v.arn_without_revision }
}

output "task_definition_revision" {
  description = "Revision of the task in a particular family."
  value       = { for k, v in aws_ecs_task_definition.main : k => v.revision }
}

output "task_definition_family" {
  description = "Task definition family"
  value       = { for k, v in aws_ecs_task_definition.main : k => v.family }
}

output "autoscaling_target_resource_id" {
  description = "Application AutoScaling resource IDs"
  value       = { for k, v in aws_appautoscaling_target.main : k => v.resource_id }
}

output "alb_request_count_scaling_policy" {
  description = "Attributes of ALB request count scaling policies"
  value       = aws_appautoscaling_policy.alb_request_count
}

output "cpu_alarm_arns" {
  description = "ARNs of CPU high CloudWatch alarms per service"
  value       = { for k, v in aws_cloudwatch_metric_alarm.cpu_high : k => v.arn }
}

output "memory_alarm_arns" {
  description = "ARNs of memory high CloudWatch alarms per service"
  value       = { for k, v in aws_cloudwatch_metric_alarm.memory_high : k => v.arn }
}

output "task_count_alarm_arns" {
  description = "ARNs of task count low CloudWatch alarms per service. Empty when Container Insights is disabled, since the metric is not published"
  value       = { for k, v in aws_cloudwatch_metric_alarm.task_count_low : k => v.arn }
}

output "service_deployment_strategy" {
  description = "Effective deployment strategy per ECS-controller service"
  value = {
    for k, v in local.svc_resolved : k => v.deployment_strategy
    if v.is_ecs_controller
  }
}

output "service_deployment_summary" {
  description = <<-EOT
    Per-service summary of the resolved launch type, network mode, scheduling
    strategy and deployment controller. The quickest plan-time check that each
    service ended up with the deployment shape you intended.
  EOT
  value = {
    for k, v in local.svc_resolved : k => {
      launch_type           = v.launch_type
      capacity_providers    = [for c in v.capacity_provider_strategy : c.capacity_provider]
      network_mode          = v.network_mode
      scheduling_strategy   = v.scheduling_strategy
      deployment_controller = v.deployment_controller
      deployment_strategy   = v.is_ecs_controller ? v.deployment_strategy : "n/a (external controller)"
      shifts_traffic        = v.shifts_traffic
    }
  }
}

##############################
# EC2 capacity outputs
##############################

output "capacity_provider_names" {
  description = "Names of the EC2 capacity providers created by this module, keyed by their map key. Use these in a service capacity_provider_strategy"
  value       = { for k, v in aws_ecs_capacity_provider.ec2 : k => v.name }
}

output "capacity_provider_arns" {
  description = "ARNs of the EC2 capacity providers created by this module"
  value       = { for k, v in aws_ecs_capacity_provider.ec2 : k => v.arn }
}

output "container_instance_autoscaling_group_names" {
  description = "Names of the container instance Auto Scaling groups, keyed by capacity provider key"
  value = merge(
    { for k, v in aws_autoscaling_group.ec2 : k => v.name },
    { for k, v in aws_autoscaling_group.ec2_mixed : k => v.name },
  )
}

output "container_instance_role_arn" {
  description = "ARN of the shared EC2 container instance IAM role, or null for a Fargate-only cluster"
  value       = try(aws_iam_role.ec2_instance[0].arn, null)
}

output "container_instance_security_group_ids" {
  description = "Security group IDs created for container instances, keyed by capacity provider key"
  value       = { for k, v in aws_security_group.ec2_instance : k => v.id }
}

output "alarm_names_for_rollback" {
  description = <<-EOT
    Per-service CloudWatch alarm names, ready to feed back into
    container_config[key].service.deployment_configuration.alarms.alarm_names
    so a deployment rolls itself back on a real signal.
  EOT
  value = {
    for k, v in local.alarm_services : k => compact([
      aws_cloudwatch_metric_alarm.cpu_high[k].alarm_name,
      aws_cloudwatch_metric_alarm.memory_high[k].alarm_name,
      try(aws_cloudwatch_metric_alarm.task_count_low[k].alarm_name, null),
    ])
  }
}


output "infrastructure_iam_role_arns" {
  description = <<-EOT
    ECS infrastructure role ARN per service - the role ECS assumes to reweight
    ALB listener rules during native traffic shifting, attach EBS volumes, and
    register VPC Lattice targets. Null for services that need none.
  EOT
  value       = local.infrastructure_iam_role_arns
}
