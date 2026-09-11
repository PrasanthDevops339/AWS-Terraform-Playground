terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = ">= 6.51.0, < 7.0.0", configuration_aliases = [aws.replica] }
    archive = { source = "hashicorp/archive", version = ">= 2.7.1, < 3.0.0" }
  }
}

locals {
  staging_name    = "staging/${var.name}/al2023-base"
  approved_name   = "golden/${var.name}/al2023-base"
  prefix          = "arn:aws"
  account_arn     = "arn:aws:iam::${var.account_id}"
  primary_base    = "arn:aws:ecr:${var.primary_region}:${var.account_id}:repository/"
  replica_base    = "arn:aws:ecr:${var.secondary_region}:${var.account_id}:repository/"
  pipeline_arn    = "arn:aws:imagebuilder:${var.primary_region}:${var.account_id}:image-pipeline/${var.name}-al2023"
  state_arn       = "arn:aws:states:${var.primary_region}:${var.account_id}:stateMachine:${var.name}-release"
  worker_repo     = split("@", split("amazonaws.com/", var.promotion_worker_image)[1])[0]
  repository_arns = ["${local.primary_base}${local.staging_name}", "${local.primary_base}${local.approved_name}", "${local.replica_base}${local.approved_name}"]
  runtime_env = {
    FACTORY_NAME        = var.name
    ACCOUNT_ID          = var.account_id
    PRIMARY_REGION      = var.primary_region
    SECONDARY_REGION    = var.secondary_region
    STAGING_REPOSITORY  = local.staging_name
    APPROVED_REPOSITORY = local.approved_name
    TABLE_NAME          = aws_dynamodb_table.releases.name
    EVIDENCE_BUCKET     = aws_s3_bucket.evidence.id
    PIPELINE_ARN        = local.pipeline_arn
    STATE_MACHINE_ARN   = local.state_arn
    RELEASE_SERIES      = var.release_series
    SOURCE_REVISION     = var.source_revision
    ALERT_TOPIC_ARN     = aws_sns_topic.alerts.arn
  }
}

data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_111:The account-root principal delegates key administration through IAM; the resource wildcard identifies this attached KMS key.
  #checkov:skip=CKV_AWS_109:KMS administration is restricted to the explicit account-root principal; service use has source restrictions.
  #checkov:skip=CKV_AWS_356:Resource star is required for a key policy and means the key to which this document is attached.

  statement {
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["${local.account_arn}:root"]
    }
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
  statement {
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.primary_region}:${var.account_id}:log-group:/aws/*${var.name}*"]
    }
  }
}
resource "aws_kms_key" "primary" {
  description             = "${var.name} factory encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_kms_key" "replica" {
  provider                = aws.replica
  description             = "${var.name} replicated ECR encryption"
  policy                  = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { AWS = "${local.account_arn}:root" }, Action = "kms:*", Resource = "*" }] })
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle {
    prevent_destroy = true
  }
}
module "staging" {
  source          = "../ecr-repository"
  name            = local.staging_name
  kms_key_arn     = aws_kms_key.primary.arn
  organization_id = var.organization_id
  approved        = false
  writer_arns     = [aws_iam_role.worker["builder"].arn]
  reader_arns     = [aws_iam_role.worker["builder"].arn, aws_iam_role.worker["publisher"].arn]
}
module "approved" {
  source          = "../ecr-repository"
  name            = local.approved_name
  kms_key_arn     = aws_kms_key.primary.arn
  organization_id = var.organization_id
  approved        = true
  writer_arns     = [aws_iam_role.worker["publisher"].arn]
  reader_arns     = []
}
module "replica" {
  source          = "../ecr-repository"
  providers       = { aws = aws.replica }
  name            = local.approved_name
  kms_key_arn     = aws_kms_key.replica.arn
  organization_id = var.organization_id
  approved        = true
  writer_arns     = ["${local.account_arn}:role/aws-service-role/replication.ecr.amazonaws.com/AWSServiceRoleForECRReplication"]
  reader_arns     = []
}

resource "aws_ecr_registry_scanning_configuration" "primary" {
  count     = var.manage_registry_configuration ? 1 : 0
  scan_type = "ENHANCED"
  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = local.staging_name
      filter_type = "WILDCARD"
    }
    repository_filter {
      filter      = local.approved_name
      filter_type = "WILDCARD"
    }
  }
  dynamic "rule" {
    for_each = lookup(var.additional_scan_rules, var.primary_region, [])
    content {
      scan_frequency = rule.value.frequency
      dynamic "repository_filter" {
        for_each = rule.value.filters
        content {
          filter      = repository_filter.value
          filter_type = "WILDCARD"
        }
      }
    }
  }
}
resource "aws_ecr_registry_scanning_configuration" "replica" {
  provider  = aws.replica
  count     = var.manage_registry_configuration ? 1 : 0
  scan_type = "ENHANCED"
  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = local.approved_name
      filter_type = "WILDCARD"
    }
  }
  dynamic "rule" {
    for_each = lookup(var.additional_scan_rules, var.secondary_region, [])
    content {
      scan_frequency = rule.value.frequency
      dynamic "repository_filter" {
        for_each = rule.value.filters
        content {
          filter      = repository_filter.value
          filter_type = "WILDCARD"
        }
      }
    }
  }
}
resource "aws_ecr_replication_configuration" "approved" {
  count = var.manage_registry_configuration ? 1 : 0
  replication_configuration {
    rule {
      destination {
        region      = var.secondary_region
        registry_id = var.account_id
      }
      repository_filter {
        filter      = "golden/${var.name}/"
        filter_type = "PREFIX_MATCH"
      }
    }
    dynamic "rule" {
      for_each = var.additional_replication_rules
      content {
        dynamic "destination" {
          for_each = rule.value.destinations
          content {
            region      = destination.value.region
            registry_id = destination.value.registry_id
          }
        }
        dynamic "repository_filter" {
          for_each = rule.value.prefixes
          content {
            filter      = repository_filter.value
            filter_type = "PREFIX_MATCH"
          }
        }
      }
    }
  }
  depends_on = [module.replica]
}
