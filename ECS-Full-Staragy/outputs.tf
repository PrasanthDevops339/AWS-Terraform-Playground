################################################################################
# Cluster Outputs
################################################################################

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = local.cluster_arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = var.create_cluster ? aws_ecs_cluster.this[0].name : split("/", var.cluster_arn)[1]
}

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = local.cluster_id
}

################################################################################
# Per-Tier Service Outputs (all keyed by tier/service name)
################################################################################

output "service_arns" {
  description = "Map of ECS service ARNs keyed by tier name"
  value       = { for k, v in aws_ecs_service.this : k => v.id }
}

output "service_names" {
  description = "Map of ECS service names keyed by tier name"
  value       = { for k, v in aws_ecs_service.this : k => v.name }
}

output "task_definition_arns" {
  description = "Map of task definition ARNs (includes revision) keyed by tier name"
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "task_definition_families" {
  description = "Map of task definition family names keyed by tier name"
  value       = { for k, v in aws_ecs_task_definition.this : k => v.family }
}

output "task_definition_revisions" {
  description = "Map of task definition revisions keyed by tier name"
  value       = { for k, v in aws_ecs_task_definition.this : k => v.revision }
}

################################################################################
# IAM Outputs
################################################################################

output "task_execution_role_arns" {
  description = "Map of task execution IAM role ARNs keyed by tier name"
  value = {
    for k, svc in var.services : k =>
    svc.create_task_execution_role ? aws_iam_role.task_execution[k].arn : svc.task_execution_role_arn
  }
}

output "task_execution_role_names" {
  description = "Map of task execution IAM role names keyed by tier name (only created roles)"
  value       = { for k, v in aws_iam_role.task_execution : k => v.name }
}

output "task_role_arns" {
  description = "Map of task IAM role ARNs keyed by tier name"
  value = {
    for k, svc in var.services : k =>
    svc.create_task_role ? aws_iam_role.task[k].arn : svc.task_role_arn
  }
}

output "task_role_names" {
  description = "Map of task IAM role names keyed by tier name (only created roles)"
  value       = { for k, v in aws_iam_role.task : k => v.name }
}

################################################################################
# Security Group Outputs
################################################################################

output "security_group_ids" {
  description = "Map of created security group IDs keyed by tier name"
  value       = { for k, v in aws_security_group.this : k => v.id }
}

output "security_group_arns" {
  description = "Map of created security group ARNs keyed by tier name"
  value       = { for k, v in aws_security_group.this : k => v.arn }
}

output "effective_security_group_ids" {
  description = "Map of all security group IDs (created + existing) attached to each tier"
  value = {
    for k, svc in var.services : k => concat(
      svc.security_group_ids,
      svc.create_security_group ? [aws_security_group.this[k].id] : []
    )
  }
}

################################################################################
# CloudWatch Outputs
################################################################################

output "cloudwatch_log_group_names" {
  description = "Map of CloudWatch log group names keyed by tier name"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}

output "cloudwatch_log_group_arns" {
  description = "Map of CloudWatch log group ARNs keyed by tier name"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.arn }
}

################################################################################
# Auto Scaling Outputs
################################################################################

output "autoscaling_target_resource_ids" {
  description = "Map of auto scaling target resource IDs keyed by tier name"
  value       = { for k, v in aws_appautoscaling_target.this : k => v.resource_id }
}

output "autoscaling_policy_arns" {
  description = "Map of auto scaling policy ARNs per tier (cpu / memory / alb_requests)"
  value = {
    for k in keys(local.autoscaling_services) : k => {
      cpu          = contains(keys(aws_appautoscaling_policy.cpu), k) ? aws_appautoscaling_policy.cpu[k].arn : null
      memory       = contains(keys(aws_appautoscaling_policy.memory), k) ? aws_appautoscaling_policy.memory[k].arn : null
      alb_requests = contains(keys(aws_appautoscaling_policy.alb_requests), k) ? aws_appautoscaling_policy.alb_requests[k].arn : null
    }
  }
}

################################################################################
# CloudWatch Alarm Outputs
################################################################################

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs keyed by tier name"
  value = {
    for k in keys(local.alarm_services) : k => {
      cpu_high           = aws_cloudwatch_metric_alarm.cpu_high[k].arn
      memory_high        = aws_cloudwatch_metric_alarm.memory_high[k].arn
      running_task_count = aws_cloudwatch_metric_alarm.running_task_count[k].arn
    }
  }
}

output "alarm_names" {
  description = "Map of CloudWatch alarm names keyed by tier name (useful for deployment_alarms input)"
  value = {
    for k in keys(local.alarm_services) : k => {
      cpu_high           = aws_cloudwatch_metric_alarm.cpu_high[k].alarm_name
      memory_high        = aws_cloudwatch_metric_alarm.memory_high[k].alarm_name
      running_task_count = aws_cloudwatch_metric_alarm.running_task_count[k].alarm_name
    }
  }
}

################################################################################
# Service Connect Outputs
################################################################################

output "service_connect_namespace_arn" {
  description = "ARN of the Service Connect HTTP namespace (shared by all tiers)"
  value       = var.enable_service_connect_namespace ? aws_service_discovery_http_namespace.this[0].arn : ""
}

output "service_connect_namespace_id" {
  description = "ID of the Service Connect HTTP namespace (shared by all tiers)"
  value       = var.enable_service_connect_namespace ? aws_service_discovery_http_namespace.this[0].id : ""
}

################################################################################
# Service Discovery Outputs
################################################################################

output "service_discovery_service_arns" {
  description = "Map of Cloud Map service discovery ARNs keyed by tier name"
  value       = { for k, v in aws_service_discovery_service.this : k => v.arn }
}

################################################################################
# Deployment Strategy Outputs
################################################################################

output "deployment_strategies" {
  description = "Map of active deployment strategies keyed by tier name"
  value       = { for k, svc in var.services : k => svc.deployment_strategy }
}

output "green_target_group_arns" {
  description = "Map of green target group ARNs keyed by tier name (non-ROLLING strategies)"
  value       = { for k, v in aws_lb_target_group.green : k => v.arn }
}

output "green_target_group_names" {
  description = "Map of green target group names keyed by tier name (non-ROLLING strategies)"
  value       = { for k, v in aws_lb_target_group.green : k => v.name }
}

output "ecs_alb_service_role_arns" {
  description = "Map of ECS ALB service role ARNs keyed by tier name (B/G traffic shifting)"
  value       = { for k, v in aws_iam_role.ecs_alb_service : k => v.arn }
}

################################################################################
# Convenience: ECS Exec Commands (per tier)
################################################################################

output "ecs_exec_commands" {
  description = "Map of AWS CLI exec-into-container commands keyed by tier name"
  value = {
    for k, svc in var.services : k => <<-EOT
      aws ecs execute-command \
        --cluster ${var.create_cluster ? aws_ecs_cluster.this[0].name : split("/", var.cluster_arn)[1]} \
        --task <TASK_ID> \
        --container ${try(svc.container_definitions[0].name, "app")} \
        --interactive \
        --command "/bin/sh"
    EOT
  }
}
