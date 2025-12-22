output "cluster_id" {
  description = "Id of the AWS ECS cluster"
  value       = var.create_cluster ? aws_ecs_cluster.main[0].id : null
}

output "cluster_arn" {
  description = "ARN that identifies the cluster."
  value       = var.create_cluster ? aws_ecs_cluster.main[0].arn : null
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = var.create_cluster ? aws_ecs_cluster.main[0].name : null
}

output "service_id" {
  description = "ARN that identifies the ECS services"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.id },
    { for k, v in aws_ecs_service.codedeploy : "${k}_codedeploy" => v.id },
    { for k, v in aws_ecs_service.external : "${k}_external" => v.id }
  )
}

output "service_name" {
  description = "Name of the ECS services"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.name },
    { for k, v in aws_ecs_service.codedeploy : "${k}_codedeploy" => v.name },
    { for k, v in aws_ecs_service.external : "${k}_external" => v.name }
  )
}

output "service_cluster" {
  description = "Cluster which the service is running on"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.cluster },
    { for k, v in aws_ecs_service.codedeploy : "${k}_codedeploy" => v.cluster },
    { for k, v in aws_ecs_service.external : "${k}_external" => v.cluster }
  )
}

output "service_desired_count" {
  description = "Number of instances of the task definition"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.desired_count },
    { for k, v in aws_ecs_service.codedeploy : "${k}_codedeploy" => v.desired_count },
    { for k, v in aws_ecs_service.external : "${k}_external" => v.desired_count }
  )
}

output "service_iam_role" {
  description = "ARN of the IAM role associated with the service"
  value = merge(
    { for k, v in aws_ecs_service.main : k => v.iam_role },
    { for k, v in aws_ecs_service.codedeploy : "${k}_codedeploy" => v.iam_role },
    { for k, v in aws_ecs_service.external : "${k}_external" => v.iam_role }
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

output "codedeploy_app_name" {
  description = "CodeDeploy application names"
  value       = { for k, v in aws_codedeploy_app.main : k => v.name }
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group names"
  value       = { for k, v in aws_codedeploy_deployment_group.main : k => v.deployment_group_name }
}

output "autoscaling_target_resource_id" {
  description = "Application AutoScaling resource IDs"
  value       = { for k, v in aws_appautoscaling_target.main : k => v.resource_id }
}
