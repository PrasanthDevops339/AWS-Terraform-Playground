output "pipeline_arn" {
  description = "Factory pipeline arn."
  value       = module.factory.pipeline_arn
}
output "repository_urls" {
  description = "Factory repository urls."
  value       = module.factory.repository_urls
}
output "staging_repository_url" {
  description = "Factory staging repository url."
  value       = module.factory.staging_repository_url
}
output "release_workflow_arn" {
  description = "Factory release workflow arn."
  value       = module.factory.release_workflow_arn
}
output "evidence_location" {
  description = "Factory evidence location."
  value       = module.factory.evidence_location
}
output "release_table_name" {
  description = "Factory release table name."
  value       = module.factory.release_table_name
}
output "alert_topic_arn" {
  description = "Factory alert topic arn."
  value       = module.factory.alert_topic_arn
}
