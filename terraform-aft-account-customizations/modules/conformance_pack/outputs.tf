output "conformance_pack_name" {
  description = "Name of the created conformance pack"
  value       = var.organization_pack ? try(aws_config_organization_conformance_pack.pack[0].name, null) : try(aws_config_conformance_pack.pack[0].name, null)
}

output "conformance_pack_arn" {
  description = "ARN of the created conformance pack"
  value       = var.organization_pack ? try(aws_config_organization_conformance_pack.pack[0].arn, null) : try(aws_config_conformance_pack.pack[0].arn, null)
}

output "conformance_pack_id" {
  description = "ID of the created conformance pack"
  value       = var.organization_pack ? try(aws_config_organization_conformance_pack.pack[0].id, null) : try(aws_config_conformance_pack.pack[0].id, null)
}
