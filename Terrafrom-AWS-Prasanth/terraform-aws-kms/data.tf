data "aws_iam_account_alias" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "baseline" {
  statement {
    sid = "PipelineAdminPermissions"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Get*",
      "kms:ReplicateKey",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:Delete*"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${local.account_id}:role/prasan-tfe-assume-role",
        "arn:aws:iam::${local.account_id}:role/${local.account_alias}-administrator-role"
      ]
    }
  }

  statement {
    sid = "ServicePermissionsPipelineAdminRoles"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.us-east-2.amazonaws.com",
        "secretsmanager.us-east-1.amazonaws.com",
        "elasticfilesystem.us-east-2.amazonaws.com",
        "elasticfilesystem.us-east-1.amazonaws.com",
        "ec2.us-east-2.amazonaws.com",
        "ec2.us-east-1.amazonaws.com",
        "dynamodb.us-east-2.amazonaws.com",
        "dynamodb.us-east-1.amazonaws.com",
        "redshift.us-east-2.amazonaws.com",
        "redshift.us-east-1.amazonaws.com",
        "s3.us-east-2.amazonaws.com",
        "s3.us-east-1.amazonaws.com",
        "cloudfront.amazonaws.com"
      ]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${local.account_id}:role/prasan-tfe-assume-role",
        "arn:aws:iam::${local.account_id}:role/${local.account_alias}-administrator-role"
      ]
    }
  }

  statement {
    sid = "BreakGlassPermissions"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:RotateKeyOnDemand"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${local.account_id}:role/cyberark-break-glass-role"]
    }
  }

  statement {
    sid = "ReadOnlyPermissions"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:Get*",
      "kms:Describe*",
      "kms:List*"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${local.account_id}:role/${local.account_alias}-platformadministrator-role",
        "arn:aws:iam::${local.account_id}:role/${local.account_alias}-securityadministrator-role",
        "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_*Developer_*"
      ]
    }
  }
}

data "aws_iam_policy_document" "custom" {
  dynamic "statement" {
    for_each = var.key_statements

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

data "aws_iam_policy_document" "replica_custom" {
  dynamic "statement" {
    for_each = var.replica_key_statements

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
    data.aws_iam_policy_document.custom.json,
    var.policy_file
  ]
}

data "aws_iam_policy_document" "replica_combined" {
  source_policy_documents = [
    data.aws_iam_policy_document.baseline.json,
    data.aws_iam_policy_document.replica_custom.json,
    var.replica_policy_file
  ]
}
