output "arn" {
  description = "The ARN of the WAF WebACL."
  value       = aws_wafv2_web_acl.main.arn
}

output "capacity" {
  description = "Web ACL capacity units (WCUs) currently being used by this web ACL."
  value       = aws_wafv2_web_acl.main.capacity
}

output "id" {
  description = "The ID of the WAF WebACL."
  value       = aws_wafv2_web_acl.main.id
}

output "tags_all" {
  description = "Map of tags assigned to the resource, including those inherited from the provider default_tags configuration block."
  value       = aws_wafv2_web_acl.main.tags_all
}

output "ipset_arn" {
  description = "The ARN of the IpSet to attach to the waf"
  value       = try(aws_wafv2_ip_set.main[0].arn, null)
}

output "rules" {
  value = var.rules
}

output "rules_json" {
  value = local.use_rules_json
}
