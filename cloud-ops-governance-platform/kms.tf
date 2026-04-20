
############################################
# CCOPS AURORA KMS KEY
############################################
module "rds-aurora-mysql-ccops-kms-key" {
  source  = "tfe/prasanth/kms/aws"
  version = "~> 2.0"

  enable_creation = true
  enable_key      = true
  key_name        = "rds_aurora_mysql_ccops_encryption_key"
  description     = "KMS key that is used for aurora cluster encryption"
  deletion_window_in_days = 8

  key_statements = [
    {
      sid       = "CloudWatchLogs"
      resources = ["*"]

      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*",
        "kms:Create*",
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

      principals = [
        {
          type        = "AWS"
          identifiers = ["*"]
        }
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalOrgID"
          values   = ["o-xxxxxxxxxx", "o-yyyyyyyyyy"]
        },
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::142174879951:role/prasan-logarchive-prd-backup-replication-role",
            "arn:aws:iam::${local.account_id}:role/prasan-operations--platformadministrator-role",
            "arn:aws:iam::${local.account_id}:role/operations--administrator"
          ]
        }
      ]
    }
  ]
}

############################################
# SNS KMS KEY
############################################
module "sns_kms" {
  source  = "tfe/prasanth/kms/aws"
  version = "~> 2.0"

  key_name    = "ccops-notifications-sns-topic-key"
  description = "CCOP Notification SNS Topic Key"

  key_statements = [
    {
      sid    = "EnableSNSEncryption"
      effect = "Allow"

      principals = [
        {
          type        = "Service"
          identifiers = [
            "sns.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
      ]

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]

      resources = ["*"]
    }
  ]
}

############################################
# STEP FUNCTION SNS KEY
############################################
module "stepfunc_kms" {
  source  = "tfe/prasanth/kms/aws"
  version = "~> 2.0"

  key_name    = "stepfunc-notifications-topic-key"
  description = "Step Function Notification SNS Topic Key"

  key_statements = [
    {
      sid    = "Allow IAM to use the key"
      effect = "Allow"

      principals = [
        {
          type        = "AWS"
          identifiers = ["*"]
        }
      ]

      actions = [
        "kms:GenerateDataKey",
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
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

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalOrgID"
          values   = ["o-xxxxxxxxxx", "o-yyyyyyyyyy"]
        },
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::142174879951:role/prasan-logarchive-prd-backup-replication-role",
            "arn:aws:iam::${local.account_id}:role/operations--administrator",
            "arn:aws:iam::${local.account_id}:role/prasan-operations--platformadministrator-role",
            "${module.lambda_compliance_ingest_lambda_role.iam_role_arn}",
            "${module.lambda_ccop_compliance_rules_execution.iam_role_arn}",
            "${module.servicenow_eventmanager_lambda_role.iam_role_arn}",
            "${module.ecs_task_role.iam_role_arn}",
            "${module.ecs_ec2_task_role.iam_role_arn}",
            "${module.ecs_tagging_task_role.iam_role_arn}",
            "${aws_iam_role.ccop_upload_state_machine_role.arn}"
          ]
        }
      ]
    },
    {
      sid    = "Allow SNS service to use the key"
      effect = "Allow"

      principals = [
        {
          type        = "Service"
          identifiers = ["sns.amazonaws.com"]
        }
      ]

      actions = [
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ]

      resources = ["*"]

      conditions = [
        {
          test     = "ArnLike"
          variable = "aws:SourceArn"
          values   = ["${module.step_function_failure_topic.sns_arn}"]
        },
        {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values   = ["${local.account_id}"]
        }
      ]
    }
  ]
}

############################################
# S3 BUCKET KMS KEY
############################################
module "ccop-s3-kms-key" {
  source  = "tfe/prasanth/kms/aws"
  version = "~> 2.0"

  key_name = "ccop-ingest-and-reporting-key"

  key_statements = [
    {
      sid = "ReplicatePermissions"

      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
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

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalOrgID"
          values   = ["o-xxxxxxxxxx", "o-yyyyyyyyyy"]
        },
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::142174879951:role/prasan-logarchive-prd-backup-replication-role",
            "arn:aws:iam::${local.account_id}:role/operations--administrator",
            "arn:aws:iam::${local.account_id}:role/prasan-operations--platformadministrator-role",
            "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_Dev_Developer_*",
            "${module.lambda_compliance_ingest_lambda_role.iam_role_arn}",
            "${module.lambda_ccop_compliance_rules_execution.iam_role_arn}",
            "${module.servicenow_eventmanager_lambda_role.iam_role_arn}",
            "${module.ecs_task_role.iam_role_arn}",
            "${module.ecs_ec2_task_role.iam_role_arn}",
            "${module.ecs_tagging_task_role.iam_role_arn}"
          ]
        }
      ]

      principals = [
        {
          type        = "AWS"
          identifiers = ["*"]
        }
      ]
    }
  ]
}

############################################
# DYNAMODB KMS KEY
############################################
module "ccop_dynamodb_kms_key" {
  source  = "tfe/prasanth/kms/aws"
  version = "~> 2.0"

  enable_creation = true
  enable_key      = true
  key_name        = "ccops_dynamodb_serverside_encryption_key"
  description     = "KMS key that is used for serverside encryption"
  deletion_window_in_days = 8

  key_statements = [
    {
      sid    = "Enable IAM User Permissions"
      effect = "Allow"

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalOrgID"
          values   = ["o-xxxxxxxxxx", "o-yyyyyyyyyy"]
        },
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::142174879951:role/prasan-logarchive-prd-backup-replication-role",
            "arn:aws:iam::${local.account_id}:role/operations--administrator",
            "arn:aws:iam::${local.account_id}:role/prasan-operations--platformadministrator-role",
            "${module.lambda_compliance_ingest_lambda_role.iam_role_arn}",
            "${module.lambda_ccop_compliance_rules_execution.iam_role_arn}",
            "${module.servicenow_eventmanager_lambda_role.iam_role_arn}",
            "${module.ecs_task_role.iam_role_arn}",
            "${module.ecs_ec2_task_role.iam_role_arn}"
          ]
        }
      ]

      principals = [
        {
          type        = "AWS"
          identifiers = ["*"]
        }
      ]

      actions   = ["kms:*"]
      resources = ["*"]
    }
  ]
}

############################################
# SERVICE NOW SECRET KMS
############################################
module "service-now-dev-secret-kms" {
  source  = "tfe/prasanth/kms/aws"
  version = "~> 2.0"

  enable_creation = true
  enable_key      = true
  key_name        = "service-now-dev-secret-kms-key"
  description     = "KMS key used for the service now dev secret"
  deletion_window_in_days = 8

  key_statements = [
    {
      sid = "ServiceNowSecret"

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalOrgID"
          values   = ["o-xxxxxxxxxx", "o-yyyyyyyyyy"]
        },
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::${local.account_id}:role/operations--administrator",
            "arn:aws:iam::${local.account_id}:role/prasan-operations--platformadministrator-role",
            "${module.servicenow_eventmanager_lambda_role.iam_role_arn}"
          ]
        }
      ]

      principals = [
        {
          type        = "AWS"
          identifiers = ["*"]
        }
      ]

      actions   = ["kms:*"]
      resources = ["*"]
    }
  ]
}

############################################
# SPLUNK TOKEN KMS
############################################
module "splunk-obsrv-token-kms" {
  source  = "tfe/prasanth/kms/aws"
  version = "~> 2.0"

  enable_creation = true
  enable_key      = true
  key_name        = "splunk-obsrv-token-kms-key"
  description     = "KMS key used for the splunk obsrv token"
  deletion_window_in_days = 8

  key_statements = [
    {
      sid = "ObsrvLambdaToken"

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalOrgID"
          values   = ["o-ieddewwfcw", "o-fwefwfvwesf"]
        },
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::${local.account_id}:role/operations--administrator",
            "arn:aws:iam::${local.account_id}:role/prasan-operations--platformadministrator-role",
            "${module.servicenow_eventmanager_lambda_role.iam_role_arn}"
          ]
        }
      ]

      principals = [
        {
          type        = "AWS"
          identifiers = ["*"]
        }
      ]

      actions   = ["kms:*"]
      resources = ["*"]
    }
  ]
}