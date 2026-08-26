output "waf_arn" {
  value = module.waf.arn
}

output "waf_capacity" {
  description = "Web ACL capacity units (WCUs) currently being used by this web ACL."
  value       = module.waf.capacity
}

output "waf_id" {
  description = "The ID of the WAF WebACL."
  value       = module.waf.id
}

output "waf_tags" {
  description = "Map of tags assigned to the resource, including those inherited from the provider default_tags configuration block."
  value       = module.waf.tags_all
}

output "ipset_arn" {
  description = "The ARN of the IpSet to attach to the waf"
  value       = try(module.waf[0].ipset_arn, null)
}
