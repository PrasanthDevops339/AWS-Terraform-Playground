locals {
  backup_tags = {
    "ops:backupschedule1" = "none"
    "ops:backupschedule2" = "none"
    "ops:backupschedule3" = "none"
    "ops:backupschedule4" = "none"
    "ops:backupschedule5" = "none"
    "ops:drschedule1"     = "none"
    "ops:drschedule2"     = "none"
    "ops:drschedule3"     = "none"
    "ops:drschedule4"     = "none"
    "ops:drschedule5"     = "none"
  }
}

resource "random_string" "module_id" {
  numeric = true
  special = false
  upper   = false
  length  = 4
}

# RDS Replica Instance (Module)
module "postgres-db-instance" {
  source = "../../.."

  subnet_ids = data.aws_subnets.data.ids
  identifier = "postgresql-replica-${random_string.module_id.result}"

  # db instance config
  engine                 = "postgres"
  engine_version         = "17"
  family                 = "postgres17" # DB parameter group
  major_engine_version   = "17"         # DB option group
  instance_class         = "db.t3.micro"
  multi_az               = true
  apply_immediately      = false
  storage_type           = "gp3"
  vpc_security_group_ids = [module.security_group.security_group_id]

  # create as read replica of source
  replicate_source_db = var.replicate_source_db

  # storage
  allocated_storage     = 80
  max_allocated_storage = 150

  # database config (replicas don't need username/password; keep port for SG clarity)
  port = 5432

  # database maintainance & backup
  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  # logging
  enabled_cloudwatch_logs_exports = ["postgresql"]
  logs_retention_period           = 1

  # monitoring
  db_events_list = ["availability", "deletion", "failover", "failure", "low storage"]

  # Snapshot name upon DB deletion
  skip_final_snapshot = true

  # Database Deletion Protection
  deletion_protection = false

  # parameters
  parameters = [
    {
      name  = "log_statement"
      value = "ddl"
    },
    {
      name  = "log_min_duration_statement"
      value = "1"
    }
  ]

  tags = local.backup_tags
}

module "security_group" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "postgres-replica-sg-${random_string.module_id.result}"
  description = "security group for database instance"
  vpc_id      = data.aws_vpc.main.id

  ########## Ingress rules ##########
  ingress_rules = [
    {
      from_port   = 5432
      to_port     = 5432
      ip_protocol = "TCP"
      cidr_ipv4   = "10.223.0.0/20"
      description = "Allow from app az1 CIDRs"
    },
    {
      from_port   = 5432
      to_port     = 5432
      ip_protocol = "TCP"
      cidr_ipv4   = "10.223.64.0/20"
      description = "Allow from app az2 CIDRs"
    },
    {
      from_port   = 5432
      to_port     = 5432
      ip_protocol = "TCP"
      cidr_ipv4   = "10.223.128.0/20"
      description = "Allow from app az3 CIDRs"
    }
  ]
}

module "kms" {
  source = "tfe.com/kms/aws"

  key_name    = "db-encrypt-postgres-replica-${random_string.module_id.result}"
  description = "db-encrypt-postgres-replica-${random_string.module_id.result}"

  key_statements = [{
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals = [{
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:role/${data.aws_iam_account_alias.current.account_alias}-platformadministrator-role"]
    }]
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:ListGrants*",
      "kms:DescribeKey",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "kms:RevokeGrant"
    ]
    resources = ["*"]
  }]
}
