############################
# Web ACL
############################

variable "description" {
  description = "(Optional) Friendly description of the WebACL."
  type        = string
  default     = null
}

variable "scope" {
  description = "(Required) Specifies whether this is for an AWS CloudFront distribution or for a regional application"
  type        = string

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "Valid values of scope are 'CLOUDFRONT', 'REGIONAL'."
  }
}

variable "waf_name" {
  description = "(Required) Friendly name of the WebACL."
  type        = string
}

############################
# Observability
############################

variable "cloudwatch_metrics_enabled" {
  description = "(Required) Whether to enable cloudwatch metrics."
  type        = bool
  default     = false
}

variable "sampled_requests_enabled" {
  description = "(Required) Whether to enable sampled_requests"
  type        = bool
  default     = false
}

############################
# IP Set
############################

variable "create_ip_set" {
  description = "(Optional) The boolean value to enable the creation of ip set and the dependent resources."
  type        = bool
  default     = true
}

variable "ipset_rule_action" {
  description = "(Required) Action that AWS WAF should take on a web request when it matches the rule's statement."
  type        = string
  default     = "allow"
}

variable "ipset_rule_priority" {
  description = "(Required) If you define more than one Rule in a WebACL, AWS WAF evaluates each request against the rules in order based on the value of priority. AWS WAF processes rules with lower priority first."
  type        = number
  default     = 500

  validation {
    condition     = var.ipset_rule_priority >= 500 && var.ipset_rule_priority <= 899
    error_message = "Value must be between 500 and 899."
  }
}

variable "ipset_addresses" {
  description = "(Optional) Contains an array of strings that specify one or more IP addresses or blocks of IP addresses in Classless Inter-Domain Routing (CIDR) notation. AWS WAF supports all address ranges for IP versions IPv4 and IPv6."
  type        = list(string)
  default     = []
}

variable "ipset_description" {
  description = "(Optional) A description of the IP set that helps with identification."
  type        = string
  default     = null
}

variable "ip_set_forwarded_ip_config" {
  description = "(Optional) Configuration for forwarded IP headers like X-Forwarded-For"
  type = object({
    header_name       = string
    fallback_behavior = string
    position          = string
  })
  default = null
}

############################
# App Rules
############################

variable "rules" {
  description = "Application Defined rules. All rule priorities must be 501-899"
  type = list(object({
    name        = string
    vendor_name = string
    priority    = number
    allow       = optional(list(string), [])
    block       = optional(list(string), [])
    captcha     = optional(list(string), [])
    challenge   = optional(list(string), [])
    count       = optional(list(string), [])
    managed_rule_group_configs = optional(object({
      aws_managed_rules_atp_rule_set = optional(object({
        login_path = string
        request_inspection = object({
          payload_type = string
          password_field = optional(object({
            identifier = string
          }))
          username_field = optional(object({
            identifier = string
          }))
        })
        response_inspection = optional(object({
          status_code = object({
            failure_codes = list(string)
            success_codes = list(string)
          })
        }))
      }))
      aws_managed_rules_bot_control_rule_set = optional(object({
        inspection_level = string
      }))
      aws_managed_rules_acfp_rule_set = optional(object({
        creation_path          = string
        registration_page_path = string
        request_inspection = object({
          payload_type = string
          email_field = optional(object({
            identifier = string
          }))
          password_field = optional(object({
            identifier = string
          }))
          username_field = optional(object({
            identifier = string
          }))
          address_fields = optional(object({
            identifier = string
          }))
          phone_number_fields = optional(object({
            identifier = string
          }))
        })
        response_inspection = optional(object({
          status_code = object({
            failure_codes = list(string)
            success_codes = list(string)
          })
        }))
      }))
    }))
  }))
  default = null

  validation {
    condition = var.rules == null || alltrue([
      for r in var.rules :
      r.priority >= 501 && r.priority <= 899
    ])
    error_message = "All application team rule priorities must be between 501 and 899."
  }
}

variable "rules_json" {
  type        = string
  description = "Application defined rules as json. All rule priorities must be 501-899"
  default     = null

  validation {
    condition = var.rules_json == null || alltrue([
      for r in jsondecode(var.rules_json) :
      r.Priority >= 501 && r.Priority <= 899
    ])
    error_message = "All rule priorities in rules_json must be between 501 and 899."
  }
}

############################
# Data Protection
############################

variable "data_protection_config" {
  description = "(Optional) AWS WAF data protection configuration."
  type = object({
    data_protection = list(object({
      action = string
      field = object({
        field_type = string
        field_keys = optional(list(string))
      })
      exclude_rate_based_details = optional(bool)
      exclude_rule_match_details = optional(bool)
    }))
  })
  default = null
}

############################
# IAM & Policy
############################

variable "create_individual_cloudwatch_policy" {
  type    = bool
  default = false
}

############################
# General
############################

variable "tags" {
  description = "A mapping of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "Optional AWS Region for regional resources. If null, resources use the configured provider region."
  type        = string
  default     = null
}
