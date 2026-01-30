# PLACEHOLDER: module outputs.tf not provided in screenshots.
# File System

output "arn" {
  description = "Amazon Resource Name of the file system"
  value       = try(aws_efs_file_system.main.arn, null)
}

output "id" {
  description = "The ID that identifies the file system (e.g., `fs-ccfcd065`)"
  value       = try(aws_efs_file_system.main.id, null)
}

output "dns_name" {
  description = "The DNS name for the filesystem per [documented convention](http://docs.aws.amazon.com/efs/latest/ug/mounting-fs-mount-cmd-dns-name.html)"
  value       = try(aws_efs_file_system.main.dns_name, null)
}

output "size_in_bytes" {
  description = "The latest known metered size (in bytes) of data stored in the file system, the value is not the exact size that the file system was at any point in time"
  value       = try(aws_efs_file_system.main.size_in_bytes, null)
}

# Mount Target(s)

output "mount_targets" {
  description = "Map of mount targets created and their attributes"
  value       = aws_efs_mount_target.main
}

# Access Point(s)

output "access_points" {
  description = "Map of access points created and their attributes"
  value       = aws_efs_access_point.main
}

# Replication Configuration

output "replication_configuration_destination_file_system_id" {
  description = "The file system ID of the replica"
  value       = try(aws_efs_replication_configuration.main[0].destination[0].file_system_id, null)
}
