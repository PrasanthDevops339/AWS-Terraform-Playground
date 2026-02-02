###############################################################################
# Outputs
###############################################################################

# EFS Outputs
output "efs_id" {
  description = "The ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_arn" {
  description = "The ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "efs_dns_name" {
  description = "The DNS name for the EFS file system"
  value       = aws_efs_file_system.main.dns_name
}

output "efs_mount_target_ids" {
  description = "The IDs of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].id
}

output "efs_mount_target_dns_names" {
  description = "The DNS names of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].dns_name
}

# Security Group Outputs
output "security_group_id" {
  description = "The ID of the EFS security group"
  value       = aws_security_group.efs.id
}

output "security_group_arn" {
  description = "The ARN of the EFS security group"
  value       = aws_security_group.efs.arn
}

# Helpful mount command
output "mount_command" {
  description = "Example command to mount the EFS file system"
  value       = "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.main.dns_name}:/ /mnt/efs"
}

# Encryption status
output "encryption_status" {
  description = "Encryption status of the EFS file system"
  value       = "ENCRYPTED AT REST (customer-managed KMS) - In-transit encryption is not enforced (mount without TLS)"
}
