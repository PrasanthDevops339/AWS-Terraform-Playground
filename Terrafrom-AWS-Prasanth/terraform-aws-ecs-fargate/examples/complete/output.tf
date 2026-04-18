########################################
# examples/complete/output.tf
########################################

# ── Cluster ──────────────────────────────────────────────────────────────────

output "cluster_id" {
  description = "ECS cluster ID"
  value       = module.three_tier_app.cluster_id
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.three_tier_app.cluster_arn
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.three_tier_app.cluster_name
}

# ── Services ──────────────────────────────────────────────────────────────────

output "service_ids" {
  description = "ECS service IDs keyed by tier (frontend, api, worker)"
  value       = module.three_tier_app.service_id
}

output "service_names" {
  description = "ECS service names keyed by tier"
  value       = module.three_tier_app.service_name
}

output "service_deployment_strategies" {
  description = "Effective deployment strategy per tier"
  value       = module.three_tier_app.service_deployment_strategy
}

# ── Task definitions ──────────────────────────────────────────────────────────

output "task_definition_arns" {
  description = "Task definition ARNs keyed by tier"
  value       = module.three_tier_app.task_definition_arn
}

output "task_definition_revisions" {
  description = "Task definition revisions keyed by tier"
  value       = module.three_tier_app.task_definition_revision
}

# ── Auto Scaling ──────────────────────────────────────────────────────────────

output "autoscaling_target_resource_ids" {
  description = "Application AutoScaling resource IDs keyed by tier"
  value       = module.three_tier_app.autoscaling_target_resource_id
}

output "cpu_scaling_policies" {
  description = "CPU target tracking scaling policies keyed by tier"
  value       = module.three_tier_app.cpu_scaling_policy
}

output "memory_scaling_policies" {
  description = "Memory target tracking scaling policies keyed by tier"
  value       = module.three_tier_app.memory_scaling_policy
}

output "alb_request_count_scaling_policies" {
  description = "ALB request count scaling policies (api tier)"
  value       = module.three_tier_app.alb_request_count_scaling_policy
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

output "cpu_alarm_arns" {
  description = "CPU high alarm ARNs keyed by tier"
  value       = module.three_tier_app.cpu_alarm_arns
}

output "memory_alarm_arns" {
  description = "Memory high alarm ARNs keyed by tier"
  value       = module.three_tier_app.memory_alarm_arns
}

output "task_count_alarm_arns" {
  description = "Task count low alarm ARNs keyed by tier"
  value       = module.three_tier_app.task_count_alarm_arns
}

# ── Load Balancers ────────────────────────────────────────────────────────────

output "frontend_alb_dns_name" {
  description = "DNS name of the public (frontend) ALB"
  value       = module.alb_public.load_balancer_dns_name
}

output "api_alb_dns_name" {
  description = "DNS name of the internal (api) ALB"
  value       = module.alb_internal.load_balancer_dns_name
}

# ── Security Groups ───────────────────────────────────────────────────────────

output "security_group_ids" {
  description = "Security group IDs per component"
  value = {
    lb_public    = module.sg_lb_public.security_group_id
    lb_internal  = module.sg_lb_internal.security_group_id
    frontend     = module.sg_frontend.security_group_id
    api          = module.sg_api.security_group_id
    worker       = module.sg_worker.security_group_id
    efs          = module.sg_efs.security_group_id
  }
}

# ── IAM ───────────────────────────────────────────────────────────────────────

output "iam_role_arns" {
  description = "IAM role ARNs per tier"
  value = {
    frontend_execution = module.iam_frontend.execution_role_arn
    api_execution      = module.iam_api.execution_role_arn
    worker_execution   = module.iam_worker.execution_role_arn
    ecs_alb_service    = aws_iam_role.ecs_alb_service.arn
  }
}

# ── EFS ───────────────────────────────────────────────────────────────────────

output "efs_id" {
  description = "EFS file system ID (api tier uploads)"
  value       = module.efs.id
}

output "efs_arn" {
  description = "EFS file system ARN (api tier uploads)"
  value       = module.efs.arn
}

# ── Service Connect ───────────────────────────────────────────────────────────

output "service_connect_namespace_arn" {
  description = "Cloud Map namespace ARN used for Service Connect"
  value       = aws_service_discovery_http_namespace.app.arn
}
