# ============================================================================
# EXCEPTION EXPIRY FEATURE (disabled by default)
# ============================================================================
# This feature automatically filters out expired exception accounts from policies
# Enable with: enable_exception_expiry = true

locals {
  # Get today's date for exception expiry comparison
  today = formatdate("YYYY-MM-DD", timestamp())

  # Filter exception_accounts to only include non-expired accounts
  # Only active when enable_exception_expiry = true
  active_exceptions = var.enable_exception_expiry ? {
    for account_id, expiry_date in var.exception_accounts :
    account_id => expiry_date
    if timecmp(expiry_date, local.today) >= 0
  } : var.exception_accounts

  # Build list of expired exceptions for validation/logging
  expired_exceptions = var.enable_exception_expiry ? {
    for account_id, expiry_date in var.exception_accounts :
    account_id => expiry_date
    if timecmp(expiry_date, local.today) < 0
  } : {}

  # Merge exception accounts into policy_vars for use in templates
  # When exception expiry is enabled, only active exceptions are included
  merged_policy_vars = merge(
    var.policy_vars,
    var.enable_exception_expiry ? {
      active_exception_accounts = keys(local.active_exceptions)
    } : {}
  )
}

resource "random_string" "main" {
  count   = var.add_random_characters == true ? 1 : 0
  length  = 6
  numeric = false
  special = false
}

resource "aws_organizations_policy" "main" {
  count = var.create_policy == true ? 1 : 0

  content = jsonencode(
    jsondecode(
      templatefile(
        "../../policies/${var.policy_name}-${var.file_date}.json",
        local.merged_policy_vars
      )
    )
  )

  name         = var.add_random_characters == true ? "${var.policy_name}-${random_string.main[0].id}" : var.policy_name
  description  = var.description
  skip_destroy = var.skip_destroy
  type         = var.type
  tags         = var.tags
}

resource "aws_organizations_policy_attachment" "main" {
  for_each = var.target_ids

  policy_id    = var.create_policy == true ? aws_organizations_policy.main[0].id : var.policy_id
  target_id    = each.value
  skip_destroy = var.skip_destroy
}
