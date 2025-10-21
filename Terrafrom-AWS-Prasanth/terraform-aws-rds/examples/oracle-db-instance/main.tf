locals {
  backup_tags = {
    "ops:backupschedule1" = "none"
    "ops:backupschedule2" = "none"
    "ops:drschedule1"     = "none"
    "ops:drschedule2"     = "none"
    "ops:drschedule3"     = "none"
    "ops:drschedule4"     = "none"
  }
}

resource "random_string" "module_id" {
  numeric = true
  special = false
  upper   = false
  length  = 4
}

module "oracle-db-instance" {
  source = "../../"

  subnet_ids = data.aws_subnets.data.ids
  identifier = "oracle-db-${random_string.module_id.result}"

  engine               = "oracle-se2"
  engine_version       = "19.0.0.0.ru-2024-10.rur-2024-10.r1"
  family               = "oracle-se2-19"
  major_engine_version = "19"
  instance_class       = "db.t3.large"
  license_model        = "license-included"

  # storage
  allocated_storage     = 80
  max_allocated_storage = 150

  # database config
  database_name                        = "TEST"
  username                             = "xb124"
  port                                 = "1521"
  manage_master_user_password          = true
  manage_master_user_password_rotation = true
  kms_key_id                           = module.kms.key_arn

  # database maintenance
  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_retention_period = 3
  backup_window           = "03:00-06:00"

  # logging
  enabled_cloudwatch_logs_exports = ["alert"]
  logs_retention_period           = 1

  # Restore demo
  # restore_to_point_in_time = { restore_time = "2024-10-16T04:43:00Z" }

  character_set_name = "AL32UTF8"

  deletion_protection = false

  vpc_security_group_ids = [module.security_group.security_group_id]

  tags = local.backup_tags
}

module "security_group" {
  source = "tfe.com/security-group/aws"

  sg_name     = "oracle-db-security-group-${random_string.module_id.result}"
  description = "security group for data base instance"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    { from_port = 1521, to_port = 1521, ip_protocol = "TCP", cidr_ipv4 = "10.223.0.0/20", description = "Allow from app az1 CIDRs" },
    { from_port = 1521, to_port = 1521, ip_protocol = "TCP", cidr_ipv4 = "10.223.64.0/20", description = "Allow from app az2 CIDRs" },
    { from_port = 1521, to_port = 1521, ip_protocol = "TCP", cidr_ipv4 = "10.223.128.0/20", description = "Allow from app az3 CIDRs" }
  ]
}

module "kms" {
  source = "tfe.com/kms/aws"

  key_name    = "db-encrypt-oracle-db-${random_string.module_id.result}"
  description = "db-encrypt-oracle-db-${random_string.module_id.result}"

  key_statements = [{
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals = [{
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:role/${data.aws_iam_account_alias.current.account_alias}-platformadministrator-role"]
    }]
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:ListGrants*", "kms:DescribeKey", "kms:Describe*", "kms:Get*", "kms:List*", "kms:RevokeGrant"]
    resources = ["*"]
  }]
}
