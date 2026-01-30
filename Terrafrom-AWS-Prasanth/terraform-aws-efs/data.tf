data "aws_caller_identity" "current" {}

data "aws_iam_account_alias" "current" {}

data "aws_iam_policy_document" "baseline" {
  version = "2012-10-17"

  statement {
    sid    = "OnlyAllowAccessViaMountTargetandpermitmountaccess"
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite"
    ]

    principals {
      type = "AWS"
      identifiers = [
        "${data.aws_caller_identity.current.account_id}"
      ]
    }

    resources = [
      "*"
    ]

    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenyUnencryptedAccessAndUploads"
    effect = "Deny"
    actions = [
      "*"
    ]
    resources = [
      "*"
    ]

    principals {
      type = "AWS"
      identifiers = [
        "${data.aws_caller_identity.current.account_id}"
      ]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "custom" {
  dynamic "statement" {
    for_each = var.efs_file_system_policy

    content {
      sid       = try(statement.value.sid, null)
      actions   = try(statement.value.actions, null)
      effect    = try(statement.value.effect, null)
      resources = try(statement.value.resources, null)

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
          values   = condition.value.values
          variable = condition.value.variable
        }
      }
    }
  }
}

data "aws_iam_policy_document" "combined" {
  source_policy_documents = [
    data.aws_iam_policy_document.baseline.json,
    data.aws_iam_policy_document.custom.json
  ]
}
