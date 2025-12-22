# Outputs for Service Connect with TLS Example

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_fargate_service_connect_tls.cluster_name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_fargate_service_connect_tls.cluster_arn
}

output "service_names" {
  description = "Names of the ECS services"
  value       = module.ecs_fargate_service_connect_tls.service_name
}

output "service_ids" {
  description = "IDs of the ECS services"
  value       = module.ecs_fargate_service_connect_tls.service_id
}

output "task_definition_arns" {
  description = "ARNs of the task definitions"
  value       = module.ecs_fargate_service_connect_tls.task_definition_arn
}

output "service_connect_namespace" {
  description = "Service Connect namespace"
  value       = aws_service_discovery_private_dns_namespace.service_connect.name
}

output "service_connect_namespace_arn" {
  description = "Service Connect namespace ARN"
  value       = aws_service_discovery_private_dns_namespace.service_connect.arn
}

output "certificate_authority_arn" {
  description = "ARN of the private certificate authority"
  value       = aws_acmpca_certificate_authority.service_connect_ca.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key for TLS encryption"
  value       = aws_kms_key.service_connect_tls.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key for TLS encryption"
  value       = aws_kms_alias.service_connect_tls.name
}

output "service_connect_tls_role_arn" {
  description = "ARN of the Service Connect TLS role"
  value       = aws_iam_role.service_connect_tls.arn
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names"
  value = {
    service_connect = aws_cloudwatch_log_group.service_connect.name
    secure_api      = aws_cloudwatch_log_group.secure_api.name
    client_service  = aws_cloudwatch_log_group.client_service.name
    database        = aws_cloudwatch_log_group.database.name
  }
}

output "security_groups" {
  description = "Security group IDs"
  value = {
    secure_api = aws_security_group.secure_api.id
    client     = aws_security_group.client.id
    database   = aws_security_group.database.id
  }
}

output "service_endpoints" {
  description = "Service endpoints within the Service Connect namespace"
  value = {
    secure_api = "https://secure-api.${var.service_connect_namespace}:${var.api_port}"
    client_app = "http://client-app.${var.service_connect_namespace}:${var.client_port}"
    database   = "postgres://postgres-db.${var.service_connect_namespace}:${var.db_port}"
  }
}

output "autoscaling_target_resource_ids" {
  description = "Auto Scaling target resource IDs"
  value       = module.ecs_fargate_service_connect_tls.autoscaling_target_resource_id
}

output "ssm_parameter_arns" {
  description = "SSM parameter ARNs"
  value = {
    db_password = aws_ssm_parameter.db_password.arn
  }
}

output "dns_configuration" {
  description = "DNS configuration for services"
  value = {
    namespace = var.service_connect_namespace
    services = {
      secure_api = "secure-api.${var.service_connect_namespace}"
      client_app = "client-app.${var.service_connect_namespace}"
      database   = "postgres-db.${var.service_connect_namespace}"
    }
  }
}