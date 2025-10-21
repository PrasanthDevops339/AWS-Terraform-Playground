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

module "mssql-db-instance" {
  source = "../../"
  count  = 1

  subnet_ids = data.aws_subnets.data.ids
  identifier = "mssql-${random_string.module_id.result}"

  # db instance config
  engine               = "sqlserver-se"
  engine_version       = "16.00.4051.1.v1"
  family               = "sqlserver-se-16.0" # DB parameter group
  major_engine_version = "16.0"              # DB option group
  instance_class       = "db.t3.large"
  apply_immediately    = false
  storage_type         = "gp3"

  # storage
  allocated_storage     = 80
  max_allocated_storage = 150
  kms_key_id            = module.kms.key_arn

  # database config
  db_name  = "bb24"
  username = "xb124"
  port     = "1433"

  # maintenance / backups
  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_retention_period = 3
  backup_window           = "03:00-06:00"

  # logging
  enabled_cloudwatch_logs_exports = ["agent", "error"]
  logs_retention_period           = 1

  # monitoring
  db_events_list = ["availability", "deletion", "failover", "failure", "low storage"]

  # snapshot policy on deletion
  skip_final_snapshot       = true
  final_snapshot_identifier = "mssql-final-db-snapshot"

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  database_insights_mode                = "advanced"

  deletion_protection = false

  # SG from module below
  vpc_security_group_ids = [module.security_group.security_group_id]

  tags = local.backup_tags
}

module "security_group" {
  source = "tfe.com/security-group/aws"

  sg_name     = "mssql-db-security-group-${random_string.module_id.result}"
  description = "security group for data base instance"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    { from_port = 1433, to_port = 1433, ip_protocol = "TCP", cidr_ipv4 = "10.223.0.0/20", description = "Allow from app az1 CIDRs" },
    { from_port = 1433, to_port = 1433, ip_protocol = "TCP", cidr_ipv4 = "10.223.64.0/20", description = "Allow from app az2 CIDRs" },
    { from_port = 1433, to_port = 1433, ip_protocol = "TCP", cidr_ipv4 = "10.223.128.0/20", description = "Allow from app az3 CIDRs" }
  ]
}

module "kms" {
  source = "tfe.com/kms/aws"

  key_name    = "db-encrypt-mssql-db-${random_string.module_id.result}"
  description = "db-encrypt-mssql-db-${random_string.module_id.result}"

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
