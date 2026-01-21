output "conformance_pack_name" {
  description = "Name of the created conformance pack"
  value       = aws_config_conformance_pack.pack.name
}

output "conformance_pack_arn" {
  description = "ARN of the created conformance pack"
  value       = aws_config_conformance_pack.pack.arn
}

output "conformance_pack_id" {
  description = "ID of the created conformance pack"
  value       = aws_config_conformance_pack.pack.id
}
