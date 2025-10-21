output "cluster_id" {
  description = "Id of the AWS ECS cluster"
  value       = aws_ecs_cluster.main[0].id
}

output "cluster_arn" {
  description = "ARN that identifies the cluster."
  value       = aws_ecs_cluster.main[0].arn
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = aws_ecs_cluster.main[0].name
}

output "service_id" {
  description = "ARN that identifies the service"
  value       = [for s in aws_ecs_service.main : s.id]
}

output "cpu_scaling_policy" {
  description = "Attributes of cpu scaling policy"
  value       = try(aws_appautoscaling_policy.cpu_scaling, null)
}

output "memory_scaling_policy" {
  description = "Attributes of memory scaling policy"
  value       = try(aws_appautoscaling_policy.memory_scaling, null)
}

output "step_scaling_policy" {
  description = "Attributes of step scaling policy"
  value       = try(aws_appautoscaling_policy.step_policy, null)
}

output "task_definition_arn" {
  description = "Full ARN of the Task Definition (including both family and revision)."
  value       = [for td in aws_ecs_task_definition.main : td.arn]
}

output "task_definition_arn_without_revision" {
  description = "ARN of the Task Definition with the trailing revision removed. This may be useful for updates."
  value       = [for td in aws_ecs_task_definition.main : td.arn_without_revision]
}

output "task_definition_revision" {
  description = "Revision of the task in a particular family."
  value       = [for td in aws_ecs_task_definition.main : td.revision]
}

output "task_definition_family" {
  description = "Task definition family"
  value       = [for td in aws_ecs_task_definition.main : td.family]
}
