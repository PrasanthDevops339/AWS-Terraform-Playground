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

module "postgres-db-instance" {
  source = "../../"

  subnet_ids = data.aws_subnets.data.ids
  identifier = "postgresql-1-${random_string.module_id.result}"

  # db instance config
  engine                      = "postgres"
  engine_version              = "17"
  family                      = "postgres17" # parameter group
  major_engine_version        = "17"         # option group (not used by PG, but kept for consistency)
  instance_class              = "db.t3.micro"
  apply_immediately           = false
  storage_type                = "gp3"
  multi_az                    = true
  kms_key_id                  = module.kms.key_arn
  manage_master_user_password = false

  # storage
  allocated_storage     = 80
  max_allocated_storage = 150

  # db cfg
  database_name = "test1"
  username      = "xb124"
  port          = "5432"

  # database maintenance
  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  # logging
  enabled_cloudwatch_logs_exports = ["postgresql"]
  logs_retention_period           = 1

  # monitoring
  db_events_list = ["availability", "deletion", "failover", "failure", "low storage"]
  sns_topic_arn  = aws_sns_topic.db_instance_alert.arn

  # snapshot & deletion
  skip_final_snapshot = true
  deletion_protection = false

  # parameters example
  parameters = [
    { name = "log_statement", value = "all" },
    { name = "log_min_duration_statement", value = "1" }
  ]

  vpc_security_group_ids = [module.security_group.security_group_id]
  tags                   = local.backup_tags
}

module "security_group" {
  source = "tfe.com/security-group/aws"

  sg_name     = "postgres-db-security-group-${random_string.module_id.result}"
  description = "security group for database instance"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    { from_port = 5432, to_port = 5432, ip_protocol = "TCP", cidr_ipv4 = "10.223.0.0/20", description = "Allow from app az1 CIDRs" },
    { from_port = 5432, to_port = 5432, ip_protocol = "TCP", cidr_ipv4 = "10.223.64.0/20", description = "Allow from app az2 CIDRs" },
    { from_port = 5432, to_port = 5432, ip_protocol = "TCP", cidr_ipv4 = "10.223.128.0/20", description = "Allow from app az3 CIDRs" }
  ]
}

module "kms" {
  source = "tfe.com/kms/aws"

  key_name    = "db-encrypt-postgres-db-${random_string.module_id.result}"
  description = "db-encrypt-postgres-db-${random_string.module_id.result}"

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
