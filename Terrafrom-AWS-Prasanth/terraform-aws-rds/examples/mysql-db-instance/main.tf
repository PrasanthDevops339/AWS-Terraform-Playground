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

module "mysql-db-instance" {
  source = "../../"

  subnet_ids = data.aws_subnets.data.ids
  identifier = "mysql-${random_string.module_id.result}"

  engine               = "mysql"
  engine_version       = "8.0"
  family               = "mysql8.0"
  major_engine_version = "8.0"
  instance_class       = "db.t4g.large"
  multi_az             = true

  # storage
  allocated_storage     = 20
  max_allocated_storage = 100
  kms_key_id            = module.kms.key_arn

  # db config
  database_name = "test"
  username      = "xb124"
  port          = "3306"

  # maintenance & backups
  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_retention_period = 3
  backup_window           = "03:00-06:00"

  # logs
  enabled_cloudwatch_logs_exports = ["error"]
  logs_retention_period           = 1

  # monitoring
  db_events_list = ["availability", "deletion", "failover", "failure", "low storage"]
  sns_topic_arn  = aws_sns_topic.db_instance_alert.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  database_insights_mode                = "standard"

  deletion_protection = false

  # parameter examples
  parameters = [
    { name = "character_set_client", value = "utf8mb4" },
    { name = "character_set_server", value = "utf8mb4" }
  ]

  # SG from module below
  vpc_security_group_ids = [module.security_group.security_group_id]

  tags = local.backup_tags
}

module "security_group" {
  source = "tfe.com/security-group/aws"

  sg_name     = "mysql-db-security-group-${random_string.module_id.result}"
  description = "security group for data base instance"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    { from_port = 3306, to_port = 3306, ip_protocol = "TCP", cidr_ipv4 = "10.223.0.0/20", description = "Allow from app az1 CIDRs" },
    { from_port = 3306, to_port = 3306, ip_protocol = "TCP", cidr_ipv4 = "10.223.64.0/20", description = "Allow from app az2 CIDRs" },
    { from_port = 3306, to_port = 3306, ip_protocol = "TCP", cidr_ipv4 = "10.223.128.0/20", description = "Allow from app az3 CIDRs" }
  ]
}

module "kms" {
  source = "tfe.com/kms/aws"

  key_name    = "db-encrypt-mysql-db-${random_string.module_id.result}"
  description = "db-encrypt-mysql-db-${random_string.module_id.result}"

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
