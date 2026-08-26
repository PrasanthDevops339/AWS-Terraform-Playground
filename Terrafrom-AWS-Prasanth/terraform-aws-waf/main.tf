resource "aws_wafv2_ip_set" "main" {
  count = var.create_ip_set ? 1 : 0

  name        = "${var.waf_name}-ipset"
  description = var.ipset_description
  scope       = var.scope
  region      = local.resource_region

  addresses          = var.ipset_addresses
  ip_address_version = "IPV4"

  tags = merge(
    var.tags,
    {
      Name = "${local.account_alias}-${var.waf_name}"
    },
    local.platform_tags,
  )
}

resource "aws_wafv2_web_acl" "main" {
  name        = "${local.account_alias}-${var.waf_name}"
  description = var.description
  scope       = var.scope
  region      = local.resource_region

  rule_json = local.use_rules_json

  dynamic "data_protection_config" {
    for_each = var.data_protection_config == null ? [] : [var.data_protection_config]
    content {
      dynamic "data_protection" {
        for_each = data_protection_config.value.data_protection
        content {
          action                     = data_protection.value.action
          exclude_rate_based_details = try(data_protection.value.exclude_rate_based_details, null)
          exclude_rule_match_details = try(data_protection.value.exclude_rule_match_details, null)
          field {
            field_type = data_protection.value.field.field_type
            field_keys = try(data_protection.value.field.field_keys, null)
          }
        }
      }
    }
  }

  default_action {
    block {}
  }

  dynamic "rule" {
    for_each = var.rules_json != null ? {} : { for r in local.default_rules : r.name => r }
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "${rule.value.name}-${var.waf_name}"
        sampled_requests_enabled   = var.sampled_requests_enabled
      }
    }
  }

  dynamic "rule" {
    for_each = var.create_ip_set ? [1] : []
    content {
      name     = "${var.waf_name}-ipset-rule"
      priority = var.ipset_rule_priority
      action {
        dynamic "allow" {
          for_each = var.ipset_rule_action == "allow" ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = var.ipset_rule_action == "block" ? [1] : []
          content {}
        }
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.main[0].arn
          dynamic "ip_set_forwarded_ip_config" {
            for_each = var.ip_set_forwarded_ip_config != null ? [var.ip_set_forwarded_ip_config] : []
            content {
              fallback_behavior = ip_set_forwarded_ip_config.value.fallback_behavior
              header_name       = ip_set_forwarded_ip_config.value.header_name
              position          = ip_set_forwarded_ip_config.value.position
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-ipset-${var.waf_name}"
        sampled_requests_enabled   = var.sampled_requests_enabled
      }
    }
  }

  dynamic "rule" {
    for_each = var.rules != null ? toset(var.rules) : toset([])
    content {
      name     = rule.value.name
      priority = rule.value.priority
      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name

          dynamic "managed_rule_group_configs" {
            for_each = lookup(rule.value, "managed_rule_group_configs", null) != null ? [rule.value.managed_rule_group_configs] : []
            content {
              dynamic "aws_managed_rules_atp_rule_set" {
                for_each = lookup(managed_rule_group_configs.value, "aws_managed_rules_atp_rule_set", null) != null ? [managed_rule_group_configs.value.aws_managed_rules_atp_rule_set] : []
                content {
                  login_path = aws_managed_rules_atp_rule_set.value.login_path
                  dynamic "request_inspection" {
                    for_each = lookup(aws_managed_rules_atp_rule_set.value, "request_inspection", null) != null ? [aws_managed_rules_atp_rule_set.value.request_inspection] : []
                    content {
                      payload_type = request_inspection.value.payload_type
                      dynamic "password_field" {
                        for_each = lookup(request_inspection.value, "password_field", null) != null ? [request_inspection.value.password_field] : []
                        content {
                          identifier = password_field.value.identifier
                        }
                      }
                      dynamic "username_field" {
                        for_each = lookup(request_inspection.value, "username_field", null) != null ? [request_inspection.value.username_field] : []
                        content {
                          identifier = username_field.value.identifier
                        }
                      }
                    }
                  }

                  dynamic "response_inspection" {
                    for_each = lookup(aws_managed_rules_atp_rule_set.value, "response_inspection", null) != null ? [aws_managed_rules_atp_rule_set.value.response_inspection] : []
                    content {
                      status_code {
                        failure_codes = response_inspection.value.status_code.failure_codes
                        success_codes = response_inspection.value.status_code.success_codes
                      }
                    }
                  }
                }
              }

              dynamic "aws_managed_rules_bot_control_rule_set" {
                for_each = lookup(managed_rule_group_configs.value, "aws_managed_rules_bot_control_rule_set", null) != null ? [managed_rule_group_configs.value.aws_managed_rules_bot_control_rule_set] : []
                content {
                  inspection_level = aws_managed_rules_bot_control_rule_set.value.inspection_level
                }
              }

              dynamic "aws_managed_rules_acfp_rule_set" {
                for_each = lookup(managed_rule_group_configs.value, "aws_managed_rules_acfp_rule_set", null) != null ? [managed_rule_group_configs.value.aws_managed_rules_acfp_rule_set] : []
                content {
                  creation_path          = aws_managed_rules_acfp_rule_set.value.creation_path
                  registration_page_path = aws_managed_rules_acfp_rule_set.value.registration_page_path

                  dynamic "request_inspection" {
                    for_each = lookup(aws_managed_rules_acfp_rule_set.value, "request_inspection", null) != null ? [aws_managed_rules_acfp_rule_set.value.request_inspection] : []
                    content {
                      payload_type = request_inspection.value.payload_type

                      dynamic "email_field" {
                        for_each = lookup(request_inspection.value, "email_field", null) != null ? [request_inspection.value.email_field] : []
                        content {
                          identifier = email_field.value.identifier
                        }
                      }

                      dynamic "password_field" {
                        for_each = lookup(request_inspection.value, "password_field", null) != null ? [request_inspection.value.password_field] : []
                        content {
                          identifier = password_field.value.identifier
                        }
                      }

                      dynamic "username_field" {
                        for_each = lookup(request_inspection.value, "username_field", null) != null ? [request_inspection.value.username_field] : []
                        content {
                          identifier = username_field.value.identifier
                        }
                      }

                      dynamic "address_fields" {
                        for_each = lookup(request_inspection.value, "address_fields", null) != null ? [request_inspection.value.address_fields] : []
                        content {
                          identifiers = address_fields.value.identifiers
                        }
                      }

                      dynamic "phone_number_fields" {
                        for_each = lookup(request_inspection.value, "phone_number_field", null) != null ? [request_inspection.value.phone_number_fields] : []
                        content {
                          identifiers = phone_number_fields.value.identifiers
                        }
                      }
                    }
                  }

                  dynamic "response_inspection" {
                    for_each = lookup(aws_managed_rules_acfp_rule_set.value, "response_inspection", null) != null ? [aws_managed_rules_acfp_rule_set.value.response_inspection] : []
                    content {
                      status_code {
                        failure_codes = response_inspection.value.status_code.failure_codes
                        success_codes = response_inspection.value.status_code.success_codes
                      }
                    }
                  }
                }
              }
            }
          }

          dynamic "rule_action_override" {
            for_each = rule.value.allow
            content {
              name = rule_action_override.value
              action_to_use {
                allow {}
              }
            }
          }

          dynamic "rule_action_override" {
            for_each = rule.value.block
            content {
              name = rule_action_override.value
              action_to_use {
                block {}
              }
            }
          }

          dynamic "rule_action_override" {
            for_each = rule.value.count
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }

          dynamic "rule_action_override" {
            for_each = rule.value.challenge
            content {
              name = rule_action_override.value
              action_to_use {
                challenge {}
              }
            }
          }

          dynamic "rule_action_override" {
            for_each = rule.value.captcha
            content {
              name = rule_action_override.value
              action_to_use {
                captcha {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "${rule.value.name}-${var.waf_name}"
        sampled_requests_enabled   = var.sampled_requests_enabled
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
    metric_name                = "cw-${var.waf_name}-waf"
    sampled_requests_enabled   = var.sampled_requests_enabled
  }

  tags = merge(
    var.tags,
    {
      Name = "${local.account_alias}-${var.waf_name}"
    },
    local.platform_tags,
  )
}
