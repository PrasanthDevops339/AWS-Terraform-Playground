# DB Instance Outputs
output "enhanced_monitoring_iam_role_name" {
  description = "The name of the monitoring role"
  value       = try(aws_iam_role.enhanced_monitoring[0].name, null)
}

output "enhanced_monitoring_iam_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the monitoring role"
  value       = try(aws_iam_role.enhanced_monitoring[0].arn, null)
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = try(aws_db_instance.main.address, null)
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = try(aws_db_instance.main.arn, null)
}

output "db_instance_identifier" {
  description = "The RDS instance identifier"
  value       = try(aws_db_instance.main.identifier, null)
}

output "db_instance_id" {
  description = "The RDS instance ID"
  value       = try(aws_db_instance.main.id, null)
}

output "db_instance_resource_id" {
  description = "The RDS Resource ID of this instance"
  value       = try(aws_db_instance.main.resource_id, null)
}

output "db_instance_status" {
  description = "The RDS instance status"
  value       = try(aws_db_instance.main.status, null)
}

output "db_name" {
  description = "The database name"
  value       = try(aws_db_instance.main.db_name, null)
}

output "db_instance_username" {
  description = "The master username"
  value       = try(aws_db_instance.main.username, null)
}

output "db_instance_port" {
  description = "The database port"
  value       = try(aws_db_instance.main.port, null)
}

output "db_instance_ca_cert_identifier" {
  description = "The CA certificate identifier"
  value       = try(aws_db_instance.main.ca_cert_identifier, null)
}

output "db_instance_domain_id" {
  description = "Directory Service domain id"
  value       = try(aws_db_instance.main.domain, null)
}

output "db_instance_domain_iam_role_name" {
  description = "IAM role name used for DS API calls"
  value       = try(aws_db_instance.main.domain_iam_role_name, null)
}

output "db_instance_password_secret_arn" {
  description = "The ARN of the random password secret (when module manages the password)"
  value       = try(aws_secretsmanager_secret.db_password[0].arn, null)
}

output "db_instance_master_user_secret_arn" {
  description = "The ARN of the master user secret (when RDS manages password)"
  value       = try(aws_db_instance.main.master_user_secret[0].secret_arn, null)
}

# Option/Subnet/Parameter group outputs
output "db_option_group_id" {
  description = "The db option group id"
  value       = try(aws_db_option_group.main[0].id, null)
}

output "db_option_group_arn" {
  description = "The ARN of the db option group"
  value       = try(aws_db_option_group.main[0].arn, null)
}

output "db_parameter_group_name" {
  description = "The db parameter group name"
  value       = try(aws_db_parameter_group.main[0].name, null)
}

output "db_parameter_group_arn" {
  description = "The ARN of the db parameter group"
  value       = try(aws_db_parameter_group.main[0].arn, null)
}

output "db_subnet_group_id" {
  description = "The db subnet group name"
  value       = try(aws_db_subnet_group.main[0].id, null)
}

output "db_subnet_group_arn" {
  description = "The ARN of the db subnet group"
  value       = try(aws_db_subnet_group.main[0].arn, null)
}
