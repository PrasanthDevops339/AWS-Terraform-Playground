data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["ins-dev-vpc-use2"]
  }
}

data "aws_subnets" "data" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-data-*"]
  }
}

data "aws_iam_policy_document" "policy_doc" {
  statement {
    sid = "EFSPermissions"

    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess"
    ]

    resources = [
      module.efs.arn
    ]
  }

  statement {
    sid    = "KMSPermissions"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey"
    ]

    resources = [module.kms.key_arn]
  }
}
