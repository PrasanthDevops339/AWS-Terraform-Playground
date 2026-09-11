output "pipeline_arn" {
  description = "Pipeline to start after prerequisite validation."
  value       = aws_imagebuilder_image_pipeline.al2023.arn
}
output "repository_urls" {
  description = "Approved ECR URLs by Region."
  value       = { (var.primary_region) = module.approved.url, (var.secondary_region) = module.replica.url }
}
output "staging_repository_url" {
  description = "Private candidate repository."
  value       = module.staging.url
}
output "release_workflow_arn" {
  description = "Trusted release state machine."
  value       = aws_sfn_state_machine.release.arn
}
output "evidence_location" {
  description = "Encrypted evidence prefix."
  value       = "s3://${aws_s3_bucket.evidence.id}/releases/"
}
output "release_table_name" {
  description = "Release versions and catalog eligibility."
  value       = aws_dynamodb_table.releases.name
}
output "alert_topic_arn" {
  description = "Connect the enterprise notification system to this topic."
  value       = aws_sns_topic.alerts.arn
}
