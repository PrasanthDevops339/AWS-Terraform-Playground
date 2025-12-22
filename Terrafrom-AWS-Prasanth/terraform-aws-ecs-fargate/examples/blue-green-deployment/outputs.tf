# Outputs for Blue/Green Deployment Example

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_fargate_blue_green.cluster_name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_fargate_blue_green.cluster_arn
}

output "service_name" {
  description = "Name of the ECS service"
  value       = module.ecs_fargate_blue_green.service_name
}

output "service_id" {
  description = "ID of the ECS service"
  value       = module.ecs_fargate_blue_green.service_id
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = module.ecs_fargate_blue_green.task_definition_arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

output "blue_target_group_arn" {
  description = "ARN of the blue target group"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "ARN of the green target group"
  value       = aws_lb_target_group.green.arn
}

output "codedeploy_app_name" {
  description = "Name of the CodeDeploy application"
  value       = module.ecs_fargate_blue_green.codedeploy_app_name
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = module.ecs_fargate_blue_green.codedeploy_deployment_group_name
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names"
  value = {
    high_cpu              = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
    high_memory           = aws_cloudwatch_metric_alarm.high_memory.alarm_name
    target_group_unhealthy = aws_cloudwatch_metric_alarm.target_group_unhealthy.alarm_name
  }
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "application_url" {
  description = "URL of the application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "test_url" {
  description = "URL for testing new deployments"
  value       = "http://${aws_lb.main.dns_name}:8080"
}