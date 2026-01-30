locals {
  effective_description = var.description != "" ? var.description : "Managed by terraform-aws-kms"
  merged_tags           = merge(local.platform_tags, var.tags)

  # Optional JSON policy docs passed in as strings from templatefile() or similar.
  extra_primary_policy_docs = [
    for d in [var.policy_file] : d
    if d != null && trim(d) != "" && trim(d) != "{}"
  ]

  extra_replica_policy_docs = [
    for d in [var.replica_policy_file] : d
    if d != null && trim(d) != "" && trim(d) != "{}"
  ]

  # Normalize statements: examples use a list of objects; the var is "any".
  primary_statements = (
    can(length(var.key_statements)) ? var.key_statements :
    (var.key_statements == {} ? [] : [var.key_statements])
  )

  replica_statements = (
    can(length(var.replica_key_statements)) ? var.replica_key_statements :
    (var.replica_key_statements == {} ? [] : [var.replica_key_statements])
  )
}

################################
# Primary key policy + resources
################################
data "aws_iam_policy_document" "primary" {
  source_policy_documents = local.extra_primary_policy_docs

  statement {
    sid       = "EnableIAMUserPermissions"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = local.primary_statements
    content {
      sid       = try(statement.value.sid, null)
      actions   = try(statement.value.actions, null)
      resources = try(statement.value.resources, ["*"])

      dynamic "principals" {
        for_each = try(statement.value.principals, [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = try(statement.value.conditions, [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count                   = var.enable_creation && var.enable_key && !var.enable_replica ? 1 : 0
  description             = local.effective_description
  deletion_window_in_days  = var.deletion_window_in_days
  enable_key_rotation      = true
  policy                  = data.aws_iam_policy_document.primary.json
  tags                    = local.merged_tags
}

resource "aws_kms_alias" "this" {
  count         = var.enable_creation && var.enable_key && !var.enable_replica ? 1 : 0
  name          = "alias/${var.key_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

###############################
# Multi-region replica (optional)
###############################
# NOTE: Replica keys require the caller to pass a secondary-region provider alias.
# Example:
#   providers = { aws = aws, aws.secondary = aws.us_east_1 }
#
# This module expects an aliased provider named "aws.secondary" when enable_replica=true.
#
data "aws_iam_policy_document" "replica" {
  source_policy_documents = local.extra_replica_policy_docs

  statement {
    sid       = "EnableIAMUserPermissions"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = local.replica_statements
    content {
      sid       = try(statement.value.sid, null)
      actions   = try(statement.value.actions, null)
      resources = try(statement.value.resources, ["*"])

      dynamic "principals" {
        for_each = try(statement.value.principals, [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = try(statement.value.conditions, [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_kms_key" "primary_for_replica" {
  count                  = var.enable_creation && var.enable_key && var.enable_replica ? 1 : 0
  description            = local.effective_description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  multi_region            = true
  policy                 = data.aws_iam_policy_document.primary.json
  tags                   = local.merged_tags
}

resource "aws_kms_alias" "primary_for_replica" {
  count         = var.enable_creation && var.enable_key && var.enable_replica ? 1 : 0
  name          = "alias/${var.key_name}"
  target_key_id = aws_kms_key.primary_for_replica[0].key_id
}

resource "aws_kms_replica_key" "this" {
  count                   = var.enable_creation && var.enable_key && var.enable_replica ? 1 : 0
  provider                = aws.secondary

  description             = local.effective_description
  deletion_window_in_days  = var.deletion_window_in_days
  primary_key_arn         = aws_kms_key.primary_for_replica[0].arn
  policy                  = data.aws_iam_policy_document.replica.json
  tags                    = local.merged_tags
}

resource "aws_kms_alias" "replica" {
  count         = var.enable_creation && var.enable_key && var.enable_replica ? 1 : 0
  provider      = aws.secondary
  name          = "alias/${var.replica_key_name != "" ? var.replica_key_name : "${var.key_name}-replica"}"
  target_key_id = aws_kms_replica_key.this[0].key_id
}
