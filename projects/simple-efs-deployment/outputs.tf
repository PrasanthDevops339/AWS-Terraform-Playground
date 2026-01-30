###############################################################################
# Outputs
###############################################################################

# EFS Outputs
output "efs_id" {
  description = "The ID of the EFS file system"
  value       = module.efs.id
}

output "efs_arn" {
  description = "The ARN of the EFS file system"
  value       = module.efs.arn
}

output "efs_dns_name" {
  description = "The DNS name for the EFS file system"
  value       = module.efs.dns_name
}

output "efs_mount_target_ids" {
  description = "The IDs of the EFS mount targets"
  value       = module.efs.mount_target_ids
}

output "efs_mount_target_dns_names" {
  description = "The DNS names of the EFS mount targets"
  value       = module.efs.mount_target_dns_name
}

# KMS Outputs
output "kms_key_arn" {
  description = "The ARN of the KMS key used for EFS encryption"
  value       = module.kms.key_arn
}

output "kms_key_id" {
  description = "The ID of the KMS key used for EFS encryption"
  value       = module.kms.key_id
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
  value       = "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${module.efs.dns_name}:/ /mnt/efs"
}
