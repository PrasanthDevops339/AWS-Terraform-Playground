terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

# AFT runs this root once per member account. One state owns both regions.
# The account ID guard prevents accidentally applying a sample to another account.
provider "aws" {
  region              = var.primary_region
  allowed_account_ids = [var.member_account_id]
}

provider "aws" {
  alias               = "secondary"
  region              = var.secondary_region
  allowed_account_ids = [var.member_account_id]
}

module "primary" {
  source = "../../modules/patch-outcome-observability"

  organization_id          = var.organization_id
  iam_role_path            = var.iam_role_path
  permissions_boundary_arn = var.permissions_boundary_arn
  archive_bucket_name      = var.archive_bucket_name
  archive_s3_prefix        = var.archive_s3_prefix
  archive_kms_key_arn      = var.archive_kms_key_arn
  archive_object_acl       = var.archive_object_acl
  enable_enrichment        = var.enable_enrichment
  include_instance_tags    = var.include_instance_tags
  rules_enabled            = var.rules_enabled
  tags                     = var.tags
}

module "secondary" {
  source    = "../../modules/patch-outcome-observability"
  providers = { aws = aws.secondary }

  create_writer_role    = false
  writer_role_arn       = module.primary.writer_role_arn
  archive_bucket_name   = var.archive_bucket_name
  archive_s3_prefix     = var.archive_s3_prefix
  archive_kms_key_arn   = var.archive_kms_key_arn
  archive_object_acl    = var.archive_object_acl
  enable_enrichment     = var.enable_enrichment
  include_instance_tags = var.include_instance_tags
  rules_enabled         = var.rules_enabled
  tags                  = var.tags
}

output "central_prerequisites" {
  value = module.primary.central_prerequisites
}

output "canary_commands" {
  value = { primary = module.primary.canary_command, secondary = module.secondary.canary_command }
}

output "regional_resources" {
  value = {
    primary = {
      writer_role_arn     = module.primary.writer_role_arn
      writer_role_created = module.primary.writer_role_created
      function_name       = module.primary.lambda_function_name
      package_bucket      = module.primary.lambda_package_bucket
      target_dlq_url      = module.primary.target_dlq_url
      lambda_dlq_url      = module.primary.lambda_dlq_url
    }
    secondary = {
      writer_role_arn     = module.secondary.writer_role_arn
      writer_role_created = module.secondary.writer_role_created
      function_name       = module.secondary.lambda_function_name
      package_bucket      = module.secondary.lambda_package_bucket
      target_dlq_url      = module.secondary.target_dlq_url
      lambda_dlq_url      = module.secondary.lambda_dlq_url
    }
  }
}
