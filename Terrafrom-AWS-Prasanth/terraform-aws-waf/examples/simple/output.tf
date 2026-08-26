output "waf_use1_arn" {
  description = "ARN of the WAF Web ACL created in us-east-1."
  value       = module.waf_use1.arn
}

output "waf_use1_capacity" {
  description = "Web ACL capacity units currently used by the WAF in us-east-1."
  value       = module.waf_use1.capacity
}

output "waf_use1_id" {
  description = "ID of the WAF Web ACL created in us-east-1."
  value       = module.waf_use1.id
}

output "waf_use1_ipset_arn" {
  description = "ARN of the IP set created in us-east-1, if enabled."
  value       = try(module.waf_use1.ipset_arn, null)
}

output "waf_use1_tags" {
  description = "Tags assigned to the WAF Web ACL created in us-east-1."
  value       = module.waf_use1.tags_all
}

output "waf_use2_arn" {
  description = "ARN of the WAF Web ACL created in us-east-2."
  value       = module.waf_use2.arn
}

output "waf_use2_capacity" {
  description = "Web ACL capacity units currently used by the WAF in us-east-2."
  value       = module.waf_use2.capacity
}

output "waf_use2_id" {
  description = "ID of the WAF Web ACL created in us-east-2."
  value       = module.waf_use2.id
}

output "waf_use2_ipset_arn" {
  description = "ARN of the IP set created in us-east-2, if enabled."
  value       = try(module.waf_use2.ipset_arn, null)
}

output "waf_use2_tags" {
  description = "Tags assigned to the WAF Web ACL created in us-east-2."
  value       = module.waf_use2.tags_all
}
