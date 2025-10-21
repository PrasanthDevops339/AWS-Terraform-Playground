# Outputs
output "db_instance_id" {
  description = "Name of the db instance"
  value       = try(module.postgres-db-instance.db_instance_id, null)
}

output "db_instance_arn" {
  description = "The ARN of the db instance"
  value       = try(module.postgres-db-instance.db_instance_arn, null)
}

output "db_name" {
  description = "The name of the db instance"
  value       = try(module.postgres-db-instance.db_name, null)
}

output "db_instance_endpoint" {
  description = "The connection endpoint"
  value       = try(module.postgres-db-instance.db_instance_endpoint, null)
}

output "db_instance_address" {
  description = "The address of the db instance"
  value       = try(module.postgres-db-instance.db_instance_address, null)
}

output "db_instance_port" {
  description = "The database port"
  value       = try(module.postgres-db-instance.db_instance_port, null)
}

output "db_instance_username" {
  description = "The db instance username"
  value       = try(module.postgres-db-instance.db_instance_username, null)
}

output "db_instance_password_secret_arn" {
  description = "The Secrets manager secret name of the db instance password"
  value       = try(module.postgres-db-instance.db_instance_password_secret_arn, module.postgres-db-instance.db_instance_master_user_secret_arn, null)
}
