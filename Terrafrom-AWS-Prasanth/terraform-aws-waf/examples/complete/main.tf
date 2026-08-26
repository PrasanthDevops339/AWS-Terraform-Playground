module "waf" {
  source = "../../"

  ipset_addresses     = ["10.0.0.0/8"]
  waf_name            = "Prasanth-waf-complete-${random_string.suffix.id}"
  scope               = "CLOUDFRONT"
  ipset_description   = "Internal Prasanth IPs"
  ipset_rule_priority = 500
  ipset_rule_action   = "allow"
  ip_set_forwarded_ip_config = {
    header_name       = "SourceIP"
    fallback_behavior = "MATCH"
    position          = "FIRST"
  }

  cloudwatch_metrics_enabled = true
  sampled_requests_enabled   = true

  data_protection_config = {
    data_protection = [
      {
        action = "HASH"
        field = {
          field_type = "SINGLE_HEADER"
          field_keys = ["authorization"]
        }
      },
      {
        action = "SUBSTITUTION"
        field = {
          field_type = "SINGLE_COOKIE"
          field_keys = ["sessionid"]
        }
        exclude_rate_based_details = true
        exclude_rule_match_details = true
      }
    ]
  }

  rules = [
    {
      name        = "AWSManagedRulesBotControlRuleSet"
      vendor_name = "AWS"
      priority    = 510
      block       = ["AWSManagedRulesBotControlRuleSet"]
      managed_rule_group_configs = {
        aws_managed_rules_bot_control_rule_set = {
          inspection_level = "COMMON"
        }
      }
    }
  ]
}

resource "random_string" "suffix" {
  length    = 4
  special   = false
  min_lower = 4
}
