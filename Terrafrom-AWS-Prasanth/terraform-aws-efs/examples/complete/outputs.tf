output "arn" {
  description = "Amazon Resource Name of the file system"
  value       = module.efs.arn
}

output "dns_name" {
  description = "dns name for filesystem"
  value       = module.efs.dns_name
}

output "id" {
  description = "The ID that identifies the file system"
  value       = module.efs.id
}

output "size_in_bytes" {
  description = "The latest known metered size (in bytes) of data stored in the file system, the value is not the exact size"
  value       = module.efs.size_in_bytes
}

output "mount_targets" {
  description = "Map of mount targets created and their attributes"
  value       = module.efs.mount_targets
}

output "access_points" {
  description = "Map of access points created and their attributes"
  value       = module.efs.access_points
}

output "replication_configuration_destination_file_system_id" {
  description = "The file system ID of the replica"
  value       = module.efs.replication_configuration_destination_file_system_id
}
