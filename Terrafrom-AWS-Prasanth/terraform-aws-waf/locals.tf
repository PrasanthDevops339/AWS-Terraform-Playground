locals {
  account_alias = data.aws_iam_account_alias.current.account_alias
  default_rules = tolist([
    {
      name                       = "AWSManagedRulesCommonRuleSet"
      vendor_name                = "AWS"
      priority                   = 300
      allow                      = tolist([])
      block                      = tolist([])
      count                      = tolist([])
      challenge                  = tolist([])
      captcha                    = tolist([])
      managed_rule_group_configs = {}
    },
    {
      name                       = "AWSManagedRulesAmazonIpReputationList"
      vendor_name                = "AWS"
      priority                   = 310
      allow                      = tolist([])
      block                      = tolist([])
      count                      = tolist([])
      challenge                  = tolist([])
      captcha                    = tolist([])
      managed_rule_group_configs = {}
    },
    {
      name                       = "AWSManagedRulesKnownBadInputsRuleSet"
      vendor_name                = "AWS"
      priority                   = 320
      allow                      = tolist([])
      block                      = tolist([])
      count                      = tolist([])
      challenge                  = tolist([])
      captcha                    = tolist([])
      managed_rule_group_configs = {}
    }
  ])

  destination_arn = {
    "us-east-1" = "arn:aws:logs:us-east-1:123456789012:destination:cw-logs-destination-kinesis-use1"
    "us-east-2" = "arn:aws:logs:us-east-2:123456789012:destination:cw-logs-destination-kinesis-use2"
  }

  module_version = split(" - ", split("## ", file("${path.module}/CHANGELOG.md"))[1])[0]

  platform_tags = {
    "platform:servicemodulename"    = "terraform-aws-waf"
    "platform:servicemoduleversion" = local.module_version
  }

  resource_region = var.scope == "CLOUDFRONT" ? "us-east-1" : coalesce(
    var.region,
    data.aws_region.current.region,
  )

  use_rules_json = var.rules_json != null ? jsonencode(concat(jsondecode(templatefile("${path.module}/default_rules.json", {
    "waf_name"                   : var.waf_name,
    "cloudwatch_metrics_enabled" : var.cloudwatch_metrics_enabled,
    "sampled_requests_enabled"   : var.sampled_requests_enabled
  })), jsondecode(var.rules_json))) : null
}
