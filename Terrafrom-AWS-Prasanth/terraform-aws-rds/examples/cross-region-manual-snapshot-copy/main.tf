################################################################################
# Automated Cross-Region RDS Backup using Lambda and EventBridge
# AWS Well-Architected Framework Implementation
# 
# This solution provides automated cross-region RDS snapshot backup using:
# - AWS Lambda for snapshot creation and management
# - EventBridge for scheduling automation
# - Works with ANY RDS engine type and option groups
# - Creates compatible option/parameter groups in secondary region
# 
# Architecture Pillars Addressed:
# - Security: Encryption, IAM roles, VPC isolation
# - Reliability: Automated cross-region backup, error handling
# - Performance: Serverless automation, efficient snapshot management
# - Cost Optimization: Event-driven execution, snapshot lifecycle management
# - Operational Excellence: Automated monitoring, CloudWatch logging
################################################################################

################################################################################
# Random ID and Local Values
################################################################################

resource "random_string" "module_id" {
  length  = 4
  special = false
  upper   = false
  numeric = true

  keepers = {
    # Force recreation if environment changes
    environment = var.environment
  }
}

locals {
  name_prefix = "${var.name}-${random_string.module_id.result}"

  # Standard tagging strategy
  common_tags = merge(var.tags, {
    Name        = local.name_prefix
    Environment = var.environment
    Module      = "terraform-aws-rds"
    Example     = "cross-region-lambda-backup"
    ManagedBy   = "terraform"
    Repository  = "terraform-aws-rds"
  })

  # Resource naming convention
  resource_names = {
    primary_kms_key   = "rds-kms-primary-${local.name_prefix}"
    secondary_kms_key = "rds-kms-secondary-${local.name_prefix}"
    security_group    = "rds-sg-primary-${local.name_prefix}"
    db_instance       = "oracle-se2-primary-${local.name_prefix}"
    backup_lambda     = "rds-backup-lambda-${local.name_prefix}"
    cleanup_lambda    = "rds-cleanup-lambda-${local.name_prefix}"
    lambda_role       = "rds-backup-lambda-role-${local.name_prefix}"
    eventbridge_rule  = "rds-backup-schedule-${local.name_prefix}"
  }

  # Oracle Standard Edition configuration - cost-optimized for testing
  oracle_config = {
    engine                 = "oracle-se2"
    engine_version         = "19.0.0.0.ru-2024-10.rur-2024-10.r1"
    family                 = "oracle-se2-19"
    major_version          = "19"
    port                   = 1521
    database_name          = "TEST"
    username               = "admin"
    parameter_group_family = "oracle-se2-19"
  }

  # Instance configuration with maximum cost optimization for testing
  instance_config = {
    class             = "db.t3.micro"
    allocated_storage = 20
    max_storage       = 50
  }

  # Oracle option group configuration
  oracle_options = [
    {
      option_name = "STATSPACK"
      description = "Oracle STATSPACK performance monitoring package"
    },
    {
      option_name = "Timezone"
      description = "Oracle timezone configuration for consistent time handling"
      option_settings = [
        {
          name  = "TIME_ZONE"
          value = "US/Eastern"
        }
      ]
    }
  ]

  # Oracle parameter group configuration optimized for t3.micro cost efficiency
  oracle_parameters = [
    {
      name        = "shared_pool_size"
      value       = "67108864" # 64MB - Minimal Oracle SGA shared pool
      description = "Memory allocated for shared SQL and PL/SQL areas"
    },
    {
      name        = "db_cache_size"
      value       = "134217728" # 128MB - Minimal database buffer cache
      description = "Memory allocated for database buffer cache"
    }
  ]
}

################################################################################
# KMS Keys for Cross-Region Encryption
################################################################################

# Primary region KMS key for RDS encryption
module "primary_kms" {
  source = "tfe.com/kms/aws"

  providers = {
    aws = aws.primary
  }

  key_name    = local.resource_names.primary_kms_key
  description = "KMS key for Oracle SE2 RDS encryption in ${var.primary_region}"

  key_statements = jsondecode(data.template_file.primary_kms_key_statements.rendered)

  tags = local.common_tags
}

# Secondary region KMS key for snapshot encryption
module "secondary_kms" {
  source = "tfe.com/kms/aws"

  providers = {
    aws = aws.secondary
  }

  key_name    = local.resource_names.secondary_kms_key
  description = "KMS key for Oracle SE2 RDS snapshot encryption in ${var.secondary_region}"

  key_statements = jsondecode(data.template_file.secondary_kms_key_statements.rendered)

  tags = local.common_tags
}

################################################################################
# Security Group
################################################################################

# Security group for RDS instance with least privilege access
module "primary_security_group" {
  source = "tfe.com/security-group/aws"

  providers = {
    aws = aws.primary
  }

  sg_name     = local.resource_names.security_group
  description = "Security group for Oracle SE2 RDS instance - ${var.environment}"
  vpc_id      = data.aws_vpc.primary.id

  # Ingress rules - restrictive by default
  ingress_rules = [
    {
      from_port   = 1521
      to_port     = 1521
      ip_protocol = "tcp"
      cidr_ipv4   = data.aws_vpc.primary.cidr_block
      description = "Oracle database access from VPC"
    }
  ]

  tags = local.common_tags
}

################################################################################
# RDS Instance (Primary) - Oracle SE2
################################################################################

# Primary Oracle SE2 RDS instance
module "oracle_primary" {
  source = "../../"

  providers = {
    aws = aws.primary
  }

  subnet_ids = data.aws_subnets.primary.ids
  identifier = "oracle-db-${random_string.module_id.result}"

  engine               = "oracle-se2"
  engine_version       = "19.0.0.0.ru-2024-10.rur-2024-10.r1"
  family               = "oracle-se2-19"
  major_engine_version = "19"
  instance_class       = "db.t3.micro"
  license_model        = "license-included"

  # storage - cost optimized
  allocated_storage     = 20
  max_allocated_storage = 50

  # database config
  database_name                        = "TEST"
  username                             = "admin"
  port                                 = "1521"
  manage_master_user_password          = true
  manage_master_user_password_rotation = true
  kms_key_id                           = module.primary_kms.key_arn

  # database maintenance
  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window

  # logging - minimal for cost optimization
  enabled_cloudwatch_logs_exports = ["alert"]

  character_set_name = "AL32UTF8"

  deletion_protection = var.enable_deletion_protection

  vpc_security_group_ids = [module.primary_security_group.security_group_id]

  # Custom option group with persistent/permanent options
  options = local.oracle_options

  # Custom parameter group settings for Oracle performance tuning
  parameters = local.oracle_parameters

  tags = local.common_tags
}

################################################################################
# Secondary Region Resources - Option and Parameter Groups Only
################################################################################

# Create parameter group in secondary region for snapshot compatibility
resource "aws_db_parameter_group" "secondary_parameter_group" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary-params"
  family      = local.oracle_config.family
  description = "Secondary region parameter group for cross-region snapshot compatibility"

  # Match primary region parameter configuration - cost optimized
  parameter {
    name  = "shared_pool_size"
    value = "67108864"
  }

  parameter {
    name  = "db_cache_size"
    value = "134217728"
  }

  tags = merge(local.common_tags, {
    Name   = "secondary-parameter-group"
    Region = "secondary"
  })
}

# Create option group in secondary region for snapshot compatibility
resource "aws_db_option_group" "secondary_option_group" {
  provider = aws.secondary

  name                     = "${local.name_prefix}-secondary-options"
  option_group_description = "Secondary region option group for cross-region snapshot compatibility"
  engine_name              = "oracle-se2"
  major_engine_version     = "19"

  # CRITICAL: IDENTICAL options as primary for compatibility
  option {
    option_name = "STATSPACK"
  }

  option {
    option_name = "Timezone"
    option_settings {
      name  = "TIME_ZONE"
      value = "US/Eastern"
    }
  }

  tags = merge(local.common_tags, {
    Name    = "secondary-option-group"
    Region  = "secondary"
    Purpose = "cross-region-snapshot-compatibility"
  })
}

################################################################################
# IAM Role for Lambda Functions
################################################################################

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = local.resource_names.lambda_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Template for Primary KMS key statements with variable substitution
data "template_file" "primary_kms_key_statements" {
  template = file("${path.module}/iam/primary-kms-key-statements.json")
  vars = {
    ACCOUNT_ID     = var.account_id
    ACCOUNT_ALIAS  = data.aws_iam_account_alias.current.account_alias
    PRIMARY_REGION = var.primary_region
  }
}

# Template for Secondary KMS key statements with variable substitution
data "template_file" "secondary_kms_key_statements" {
  template = file("${path.module}/iam/secondary-kms-key-statements.json")
  vars = {
    ACCOUNT_ID                = var.account_id
    ACCOUNT_ALIAS             = data.aws_iam_account_alias.current.account_alias
    PRIMARY_REGION            = var.primary_region
    SECONDARY_REGION          = var.secondary_region
    LAMBDA_EXECUTION_ROLE_ARN = aws_iam_role.lambda_execution_role.arn
  }
}

# Template for Lambda RDS policy with variable substitution
data "template_file" "lambda_rds_policy" {
  template = file("${path.module}/iam/lambda-rds-policy.json")
  vars = {
    PRIMARY_KMS_KEY_ARN   = module.primary_kms.key_arn
    SECONDARY_KMS_KEY_ARN = module.secondary_kms.key_arn
  }
}

# IAM policy for Lambda RDS operations
resource "aws_iam_role_policy" "lambda_rds_policy" {
  name   = "${local.resource_names.lambda_role}-rds-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.template_file.lambda_rds_policy.rendered
}

# Attach basic execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

################################################################################
# Lambda Functions for Automated Backup
################################################################################

# RDS Backup Lambda function using terraform-aws-lambda module
module "rds_backup_lambda" {
  source = "tfe.com/lambda/aws"

  # Required parameters
  lambda_name     = local.resource_names.backup_lambda
  lambda_role_arn = aws_iam_role.lambda_execution_role.arn

  # Lambda configuration
  lambda_description             = "Automated cross-region RDS backup function - handles any RDS engine type and option groups"
  lambda_handler                 = "lambda_function.lambda_handler"
  runtime                        = "python3.12"
  timeout                        = var.lambda_timeout
  memory_size                    = 256
  reserved_concurrent_executions = 1 # Ensure only one backup runs at a time
  publish                        = false
  ephemeral_storage              = 512 # /tmp storage in MB

  # Package configuration
  lambda_script_dir = "${path.module}/lambda"
  upload_to_s3      = true
  package_type      = "zip"

  # Environment variables
  environment = {
    PRIMARY_REGION         = var.primary_region
    SECONDARY_REGION       = var.secondary_region
    RETENTION_DAYS         = tostring(var.snapshot_retention_days)
    SECONDARY_KMS_KEY      = module.secondary_kms.key_arn
    SECONDARY_OPTION_GROUP = aws_db_option_group.secondary_option_group.name
  }

  # EventBridge trigger configuration
  allowed_triggers = {
    eventbridge = {
      principal  = "events.amazonaws.com"
      source_arn = aws_cloudwatch_event_rule.rds_backup_schedule.arn
    }
  }

  # Logging configuration
  logging_config = {
    log_format            = "JSON"
    log_group             = "/applications/${local.resource_names.backup_lambda}"
    system_log_level      = "INFO"
    application_log_level = "INFO"
  }

  # X-Ray tracing configuration
  tracing_config = {
    mode = "Active"
  }

  # Dead letter queue configuration for error handling
  dead_letter_config = {
    target_arn = "arn:aws:sqs:${var.primary_region}:${var.account_id}:${local.resource_names.backup_lambda}-dlq"
  }

  # Security configuration
  kms_key_arn = module.primary_kms.key_arn

  # Resource tags
  tags = merge(local.common_tags, {
    Function    = "rds-backup-automation"
    Purpose     = "cross-region-snapshot-management"
    Runtime     = "python3.12"
    Trigger     = "eventbridge-scheduled"
    Description = "Automated RDS backup with universal engine support"
  })

  # Package tags for S3 deployment package
  package_tags = {
    PackageType = "lambda-deployment"
    CreatedBy   = "terraform-aws-lambda"
    Purpose     = "rds-backup-automation"
  }

  # Test events for Lambda function testing
  test_events = [
    {
      event_name = "test-backup-event"
      event_value = {
        db_instance_identifier = "test-oracle-instance"
        test_mode              = true
      }
    },
    {
      event_name = "scheduled-backup-event"
      event_value = {
        db_instance_identifier = module.oracle_primary.db_instance_identifier
        scheduled              = true
        retention_override     = 14
      }
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_db_option_group.secondary_option_group,
    module.secondary_kms
  ]
}

################################################################################
# EventBridge for Automated Scheduling
################################################################################

# EventBridge rule for scheduled backups
resource "aws_cloudwatch_event_rule" "rds_backup_schedule" {
  name                = local.resource_names.eventbridge_rule
  description         = "Trigger RDS cross-region backup Lambda"
  schedule_expression = var.lambda_schedule

  tags = local.common_tags
}

# EventBridge target - Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.rds_backup_schedule.name
  target_id = "RDSBackupLambdaTarget"
  arn       = module.rds_backup_lambda.lambda_function_arn

  input = jsonencode({
    db_instance_identifier = module.oracle_primary.db_instance_identifier
  })
}

# Note: Lambda permission is now handled by the terraform-aws-lambda module
# through the allowed_triggers configuration