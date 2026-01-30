## Deprecated outputs
output "key_id" {
  description = "KMS key ID"
  value       = var.enable_replica == false ? concat(aws_kms_key.main.*.id, [""])[0] : ""
}

output "key_replica_id" {
  description = "KMS key replica ID"
  value       = var.enable_replica == true ? concat(aws_kms_replica_key.main.*.id, [""])[0] : ""
}

output "key_arn" {
  description = "KMS key arn"
  value       = var.enable_replica == false ? concat(aws_kms_key.main.*.arn, [""])[0] : ""
}

output "key_replica_arn" {
  description = "KMS key replica arn"
  value       = var.enable_replica == true ? concat(aws_kms_replica_key.main.*.arn, [""])[0] : ""
}

output "key_name" {
  value       = join("", aws_kms_alias.main.*.name)
  description = "Alias name"
}

output "key_replica_name" {
  value       = join("", aws_kms_alias.replica.*.name)
  description = "Alias replica name"
}

## New outputs
output "primary_key_id" {
  description = "KMS primary key ID"
  value       = var.enable_replica == true && var.enable_region_argument == true ? concat(aws_kms_key.primary.*.id, [""])[0] : ""
}

output "primary_key_arn" {
  description = "Primary KMS key arn"
  value       = var.enable_replica == true && var.enable_region_argument == true ? concat(aws_kms_key.primary.*.arn, [""])[0] : ""
}

output "primary_key_name" {
  value       = join("", aws_kms_alias.primary.*.name)
  description = "Alias primary key name"
}

output "secondary_key_id" {
  description = "KMS secondary key ID"
  value       = var.enable_replica == true && var.enable_region_argument == true ? concat(aws_kms_replica_key.secondary.*.id, [""])[0] : ""
}

output "secondary_key_arn" {
  description = "Secondary KMS key arn"
  value       = var.enable_replica == true && var.enable_region_argument == true ? concat(aws_kms_replica_key.secondary.*.arn, [""])[0] : ""
}

output "secondary_key_name" {
  value       = join("", aws_kms_alias.secondary.*.name)
  description = "Alias secondary key name"
}

