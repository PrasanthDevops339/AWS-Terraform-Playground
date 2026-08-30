output "alb_dns_name" {
  description = "Production endpoint. Port 80 serves live traffic, port 8080 serves the green task set for smoke tests"
  value       = aws_lb.this.dns_name
}

output "blue_target_group_arn" {
  description = "Blue target group. ECS registers task IPs here itself"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "Green target group, the alternate ECS shifts traffic to"
  value       = aws_lb_target_group.green.arn
}

output "production_listener_rule_arn" {
  description = "The listener rule whose weights ECS rewrites during a deployment"
  value       = aws_lb_listener_rule.production.arn
}

output "infrastructure_iam_role_arns" {
  description = "ECS infrastructure role the module created to reweight the listener rule. Proof that no CodeDeploy service role is involved"
  value       = module.ecs.infrastructure_iam_role_arns
}

output "deployment_summary" {
  description = "Resolved deployment shape. deployment_controller should read ECS, not CODE_DEPLOY"
  value       = module.ecs.service_deployment_summary
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "service_names" {
  description = "ECS service names keyed by container_config key. Named consistently with the other examples so runbook loops work across all of them"
  value       = module.ecs.service_name
}
