
data "aws_region" "current" {}

# Used for mysqlrds.tf
data "aws_vpc" "vpc_id" {
  filter {
    name   = "tag:Name"
    values = ["prasan-*-vpc-use2"]
  }
}

# Used for mysqlrds.tf
data "aws_subnets" "subnet_ids" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc_id.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-data-*"]
  }
}

# Get VPC IDs
data "aws_ssm_parameter" "vpc_use2" {
  name = "/network/prasan-vpc-use2"
}

# Get web subnet ids
data "aws_ssm_parameter" "subnet-web-ids" {
  name = "/network/subnet-web-ids"
}

# Get app subnet ids
data "aws_ssm_parameter" "subnet-app-ids" {
  name = "/network/subnet-app-ids"
}

# Get account name
data "aws_ssm_parameter" "account_name" {
  name = "/aft/account-request/custom-fields/account_name"
}

# resource policy document to access secrets
data "aws_iam_policy_document" "secretmanager_policy_document" {

  statement {
    sid = "LambdaReadWrite"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        "${data.aws_caller_identity.current.account_id}"
      ]
    }

    resources = ["*"]
  }
}

# lambda execution role policy document
data "aws_iam_policy_document" "lambda_execution_role_policy_document" {

  statement {
    sid = "AllowmanagingSecretFromLambda"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
      "secretsmanager:ListSecretVersionIds"
    ]

    effect = "Allow"

    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret/*"
    ]
  }

  statement {
    sid = "AllowLambdaToWriteToCloudwatch"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    effect = "Allow"

    resources = [
      "*"
    ]
  }

  statement {
    sid = "GetRandomPassword"

    actions = [
      "secretsmanager:GetRandomPassword"
    ]

    effect = "Allow"

    resources = [
      "*"
    ]
  }

  statement {
    sid = "AllowLambdaToAccessEC2"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DetachNetworkInterface"
    ]

    effect = "Allow"

    resources = [
      "*"
    ]
  }

  statement {
    sid = "AllowLambdaAccessToKMS"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey"
    ]

    effect = "Allow"

    resources = [
      module.secret_key_db.key_arn
    ]
  }
}

data "aws_iam_policy_document" "sns_topic_policy" {

  policy_id = "__default_policy_ID__"

  statement {

    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:GetTopicAttributes",
      "SNS:AddPermission",
    ]

    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        "${data.aws_caller_identity.current.account_id}"
      ]
    }

    resources = [
      module.sns.sns_arn,
    ]

    sid = "1"
  }

  statement {

    actions = [
      "SNS:Publish"
    ]

    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "cloudwatch.amazonaws.com"
      ]
    }

    resources = [
      module.sns.sns_arn,
    ]

    sid = "2"
  }
}

data "aws_iam_policy_document" "service-now-dev-secret" {

  statement {
    sid = "AllowSecretaccess"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        "*"
      ]
    }

    resources = [
      "${module.secrets_manager_service_now_dev.secret_arn}"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"

      values = [
        "o-ie70f219nn",
        "o-ie1yc8zvv5"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"

      values = [
        "${module.servicenow_eventmanager_lambda_role.iam_role_arn}"
      ]
    }
  }
}

# resource policy document to access secrets
data "aws_iam_policy_document" "splunk-obsrv-token" {

  statement {
    sid = "AllowSecretaccess"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        "*"
      ]
    }

    resources = [
      "${module.secrets_manager_splunk_obsrv_dev.secret_arn}"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"

      values = [
        "o-ie70f219nn",
        "o-ie1yc8zvv5"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"

      values = [
        module.servicenow_eventmanager_lambda_role.iam_role_arn,
        module.lambda_compliance_ingest_lambda_role.iam_role_arn,
        module.lambda_database_bootstrap_role.iam_role_arn,
        module.lambda_database_iam_auth_role.iam_role_arn,
        module.lambda_ccop_compliance_rules_execution.iam_role_arn,
        module.splunk_observ_lambda_role.iam_role_arn
      ]
    }
  }
}

data "aws_iam_policy_document" "sns_stepfunc_policy_document" {

  policy_id = "__default_policy_ID__"

  statement {

    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:GetTopicAttributes",
      "SNS:AddPermission",
    ]

    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        "${data.aws_caller_identity.current.account_id}"
      ]
    }

    resources = [
      module.step_function_failure_topic.sns_arn,
    ]

    sid = "1"
  }

  statement {

    actions = [
      "SNS:Publish"
    ]

    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "cloudwatch.amazonaws.com"
      ]
    }

    resources = [
      module.step_function_failure_topic.sns_arn,
    ]

    sid = "2"
  }
}