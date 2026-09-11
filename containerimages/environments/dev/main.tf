provider "aws" {
  region              = var.primary_region
  allowed_account_ids = [var.account_id]
  default_tags { tags = merge(var.tags, { ManagedBy = "Terraform", Factory = var.name }) }
}
provider "aws" {
  alias               = "replica"
  region              = var.secondary_region
  allowed_account_ids = [var.account_id]
  default_tags { tags = merge(var.tags, { ManagedBy = "Terraform", Factory = var.name }) }
}
module "factory" {
  access_log_bucket_name        = var.access_log_bucket_name
  source                        = "../../modules/factory"
  providers                     = { aws = aws, aws.replica = aws.replica }
  name                          = var.name
  account_id                    = var.account_id
  organization_id               = var.organization_id
  primary_region                = var.primary_region
  secondary_region              = var.secondary_region
  vpc_id                        = var.vpc_id
  subnet_id                     = var.subnet_id
  egress_cidrs                  = var.egress_cidrs
  build_host_ami                = var.build_host_ami
  parent_image                  = var.parent_image
  source_revision               = var.source_revision
  recipe_version                = var.recipe_version
  release_series                = var.release_series
  certificate_bundle            = var.certificate_bundle
  package_repository_file       = var.package_repository_file
  package_release               = var.package_release
  promotion_worker_image        = var.promotion_worker_image
  schedule_enabled              = var.schedule_enabled
  scan_timeout_seconds          = var.scan_timeout_seconds
  replication_timeout_seconds   = var.replication_timeout_seconds
  manage_registry_configuration = var.manage_registry_configuration
  additional_scan_rules         = var.additional_scan_rules
  additional_replication_rules  = var.additional_replication_rules
  tags                          = var.tags
}
