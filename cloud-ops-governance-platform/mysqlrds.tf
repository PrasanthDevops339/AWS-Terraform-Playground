#----------------------------
# Aurora Cluster - CCOPS
#----------------------------
module "aurora-mysql-ccops-cluster" {
  source  = "tfe.prasanth.com/prasanth-insurance/rds-aurora/aws"
  version = "1.0.4"

  rds_cluster_name = "aurora-mysql-ccops"

  # rds cluster config
  engine                 = "aurora-mysql"
  engine_version         = "8.0"
  replica_count          = 1
  instance_type          = "db.r5.large"
  apply_immediately      = true
  subnet_ids             = data.aws_subnets.subnet_ids.ids
  vpc_security_group_ids = [module.security-group.security_group_id]

  # database config
  database_name = "ccops"
  username      = "ccops"
  port          = "3306"

  # database maintainance
  preferred_maintenance_window = "Mon:00:00-Mon:03:00"
  preferred_backup_window      = "03:00-06:00"
  kms_key_id                   = module.rds-aurora-mysql-ccops-kms-key.key_arn

  # db parameter group
  family                              = "aurora-mysql8.0"
  manage_master_user_password         = true
  manage_master_user_password_rotation = true
  db_cluster_activity_stream_mode     = "async"

  create_db_cluster_activity_stream = true
  activity_stream_kms_key           = module.rds-aurora-mysql-ccops-kms-key.key_arn

  # Snapshot name upon DB deletion
  skip_final_snapshot = true

  # Database Deletion Protection
  deletion_protection = false

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["audit", "error", "general", "slowquery"]
}

#Run SQL to configure database
# Gated by var.enable_database_bootstrap_invocation so non-prod environments
# (or releases that don't need schema changes) can skip the auto-invoke.
resource "aws_lambda_invocation" "run_database_bootstrap_lambda" {
  count = var.enable_database_bootstrap_invocation ? 1 : 0

  function_name = module.lambda_database_bootstrap.lambda_function_name

  input = jsonencode({
    key1 = "value1"
  })

  # Re-invoke the bootstrap Lambda whenever the SQL file, the script, or the
  # underlying lambda package changes. lambda_source_hash covers every file in
  # the zip; the explicit filesha256 entries are kept as belt-and-suspenders
  # in case the module ever stops surfacing source_code_hash.
  triggers = {
    mysql_config_hash     = filesha256("${path.module}/scripts/databasebootstrap/mysql_config.txt")
    bootstrap_script_hash = filesha256("${path.module}/scripts/databasebootstrap/database_bootstrap.py")
    lambda_source_hash    = module.lambda_database_bootstrap.lambda_source_code_hash
  }

  depends_on = [
    module.aurora-mysql-ccops-cluster,
    module.lambda_database_bootstrap
  ]
}

output "database_bootstrap_lambda_result" {
  value = var.enable_database_bootstrap_invocation ? jsondecode(aws_lambda_invocation.run_database_bootstrap_lambda[0].result) : null
}
