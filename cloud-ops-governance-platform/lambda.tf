#----------------------------------------------------------------------------------lambda.tf-------------------------------------------------------------
#All lambda functions should be created in this file.

###############################LAMBDA SERVICENOW EVENT MANAGER#############################################################
###########################################################################################################################
module "lambda_servicenow_eventmanager" {
  upload_to_s3        = true
  source              = "tfe.prasn.com/prasn-/lambda/aws"
  version             = "1.2.0"
  lambda_name         = "ccop-servicenow-eventmanager"
  lambda_description  = "a Lambda Function Lambda Function for SNOW integration w/ read permissions to the SNOW credentials stored in AWS Secrets Manage"
  lambda_script_dir   = "./scripts/serviceNowEventManagerLambda/"
  lambda_handler      = "servicenow_eventmanager.lambda_handler"
  lambda_role_arn     = module.servicenow_eventmanager_lambda_role.iam_role_arn
  architectures       = ["x86_64"]
  memory_size         = 2048
  timeout             = 20
  runtime             = var.python_lambda_layer_runtime
  lambda_bucket_name  = local.lambda_bucket_name
  layers              = [
    aws_lambda_layer_version.advanced_python_wrapper_mysql[0].arn,
    aws_lambda_layer_version.pandas_numpy_xlsxwriter[0].arn,
    aws_lambda_layer_version.pysnow[0].arn,
    aws_lambda_layer_version.otel[0].arn,
    local.splunk_layer_arn
  ]

  vpc_config = {
    subnet_ids          = local.app_subnet_list
    security_group_ids  = ["${module.lambda_database_access_security_group.security_group_id}"]
  }

  logging_config = {
    log_format      = "Text"
    log_group_name  = "/application_logs"
  }

  environment = {
    S3_BUCKET                  = module.ccop_ingest_reporting_bucket.bucket_name
    DEFAULT_ASSIGNMENT_GROUP   = "Cloud Enblmnt-Cloud Operations"
    INGEST_PREFIX              = "ingest/aws-config/"
    KB_ARTICLE_URL             = "https://prasnprod.service-now.com/kb_view.do?sys_kb_id=d409b489c3ea16d83354392f0501311f"
    SNOW_INSTANCE              = "prasn${var.environment}"
    SNOW_SECRET_NAME           = module.secrets_manager_service_now_dev.secret_arn
    TICKET_CATEGORY            = "Application -> Other Issue"
    db_host                    = module.aurora-mysql-ccops-cluster.rds_cluster_endpoint
    db_user                    = var.database_rw_user
    db_port                    = "3306"
    db_name                    = module.aurora-mysql-ccops-cluster.rds_cluster_database_name
    region                     = "us-east-2"
    rules_table                = module.ccop_dynamodb_table.dynamodb_table_id
    SPLUNK_REALM               = "us0"
    SPLUNK_ACCESS_TOKEN        = ""
    AWS_LAMBDA_EXEC_WRAPPER    = "/opt/otel-instrument"
    OTEL_SERVICE_NAME          = "Service Now Event Manager Lambda"
    OTEL_RESOURCE_ATTRIBUTES   = "deployment.environment=dev"
    OTEL_PYTHON_LOG_CORRELATION = "true"
    PYTHONPATH                 = "/opt/python/lib/python3.12/site-packages"
  }
}

############################################################################################################################
##################################LAMBDA COMPLIANCE DB INGESTION###########################################################
#Step 6 - ingestion of compliance data from S3 bucket into Aurora DB. Triggered by Step 5 Step Function
############################################################################################################################
module "lambda_compliance_ingest" {
  upload_to_s3        = true
  source              = "tfe.prasn.com/prasn-/lambda/aws"
  version             = "1.2.0"
  lambda_name         = "ccop-compliance-ingest"
  lambda_description  = "a Lambda Function for compliance DB ingest"
  lambda_script_dir   = "./scripts/complianceIngestLambda/"
  lambda_handler      = "compliance_ingest.lambda_handler"
  lambda_role_arn     = module.lambda_compliance_ingest_lambda_role.iam_role_arn
  architectures       = ["x86_64"]
  memory_size         = 2048
  timeout             = 20
  runtime             = var.python_lambda_layer_runtime
  lambda_bucket_name  = local.lambda_bucket_name
  layers              = [
    aws_lambda_layer_version.advanced_python_wrapper_mysql[0].arn,
    local.splunk_layer_arn,
    aws_lambda_layer_version.otel[0].arn
  ]

  vpc_config = {
    subnet_ids          = local.app_subnet_list
    security_group_ids  = ["${module.lambda_database_access_security_group.security_group_id}"]
  }

  logging_config = {
    log_format      = "Text"
    log_group_name  = "/application_logs"
  }

  environment = {
    target_bucket              = module.ccop_ingest_reporting_bucket.bucket_name
    db_host                   = module.aurora-mysql-ccops-cluster.rds_cluster_endpoint
    db_user                   = var.database_rw_user
    db_port                   = "3306"
    db_name                   = module.aurora-mysql-ccops-cluster.rds_cluster_database_name
    region                    = "us-east-2"
    SPLUNK_REALM              = "us0"
    SPLUNK_ACCESS_TOKEN       = ""
    AWS_LAMBDA_EXEC_WRAPPER   = "/opt/otel-instrument"
    OTEL_SERVICE_NAME         = "Compliance DB Ingest Lambda"
    OTEL_RESOURCE_ATTRIBUTES  = "deployment.environment=dev"
    OTEL_PYTHON_LOG_CORRELATION = "true"
    PYTHONPATH                = "/opt/python/lib/python3.12/site-packages"
  }
}

############################################################################################################################
#############################################LAMBDA DATABASE BOOTSATRAP####################################################
############################################################################################################################
module "lambda_database_bootstrap" {
  version             = "1.2.0"
  lambda_name         = "ccop-database-bootstrap"
  lambda_description  = "a Lambda Function to configure the database after it is created"
  lambda_script_dir   = "./scripts/databasebootstrap/"
  lambda_handler      = "database_bootstrap.lambda_handler"
  lambda_role_arn     = module.lambda_database_bootstrap_role.iam_role_arn
  architectures       = ["x86_64"]
  memory_size         = 2048
  timeout             = 20
  runtime             = var.python_lambda_layer_runtime
  lambda_bucket_name  = local.lambda_bucket_name
  layers              = [aws_lambda_layer_version.advanced_python_wrapper_mysql[0].arn,local.splunk_layer_arn,aws_lambda_layer_version.otel[0].arn]

  vpc_config = {
    subnet_ids          = local.app_subnet_list
    security_group_ids  = ["${module.lambda_database_access_security_group.security_group_id}"]
  }

  logging_config = {
    log_format      = "Text"
    log_group_name  = "/application_logs"
  }

  environment = {
    database_name              = module.aurora-mysql-ccops-cluster.rds_cluster_database_name
    database_secret_arn        = module.aurora-mysql-ccops-cluster.rds_master_user_secret[0].secret_arn
    proxy_host_name            = module.aurora-mysql-ccops-cluster.rds_cluster_endpoint
    SPLUNK_REALM               = "us0"
    SPLUNK_ACCESS_TOKEN        = ""
    AWS_LAMBDA_EXEC_WRAPPER    = "/opt/otel-instrument"
    OTEL_SERVICE_NAME          = "Database Bootstrap Lambda"
    OTEL_RESOURCE_ATTRIBUTES   = "deployment.environment=dev"
    OTEL_PYTHON_LOG_CORRELATION = "true"
    PYTHONPATH                 = "/opt/python/lib/python3.12/site-packages"
  }

  depends_on = [aws_lambda_layer_version.advanced_python_wrapper_mysql]
}

############################################################################################################################
#############################################LAMBDA DATABASE IAM AUTH######################################################
############################################################################################################################
module "lambda_iam_auth" {
  upload_to_s3        = true
  source              = "tfe.prasn.com/prasn-/lambda/aws"
  version             = "1.2.0"
  lambda_name         = "ccop-iam-auth"
  lambda_description  = "a Lambda Function to demonstrate database authentication using IAM"
  lambda_script_dir   = "./scripts/databaseiamauth/"
  lambda_handler      = "database_iam_auth.lambda_handler"
  lambda_role_arn     = module.lambda_database_iam_auth_role.iam_role_arn
  architectures       = ["x86_64"]
  memory_size         = 2048
  timeout             = 20
  runtime             = var.python_lambda_layer_runtime
  lambda_bucket_name  = local.lambda_bucket_name
  layers              = [aws_lambda_layer_version.advanced_python_wrapper_mysql[0].arn,local.splunk_layer_arn,aws_lambda_layer_version.otel[0].arn]

  vpc_config = {
    subnet_ids          = local.app_subnet_list
    security_group_ids  = ["${module.lambda_database_access_security_group.security_group_id}"]
  }

  logging_config = {
    log_format      = "Text"
    log_group_name  = "/application_logs"
  }

  environment = {
    database_name              = module.aurora-mysql-ccops-cluster.rds_cluster_database_name
    proxy_host_name            = module.aurora-mysql-ccops-cluster.rds_cluster_endpoint
    database_user_name         = var.database_rw_user
    SPLUNK_REALM               = "us0"
    SPLUNK_ACCESS_TOKEN        = ""
    AWS_LAMBDA_EXEC_WRAPPER    = "/opt/otel-instrument"
    OTEL_SERVICE_NAME          = "Database IAM AUTH Lambda"
    OTEL_RESOURCE_ATTRIBUTES   = "deployment.environment=dev"
    OTEL_PYTHON_LOG_CORRELATION = "true"
    PYTHONPATH                 = "/opt/python/lib/python3.12/site-packages"
  }

  depends_on = [aws_lambda_layer_version.advanced_python_wrapper_mysql]
}

############################################################################################################################
#############################################LAMBDA CCOP COMPLIANCE RULES EXECUTION########################################
############################################################################################################################
module "lambda_compliance_execution" {
  upload_to_s3        = true
  source              = "tfe.prasn.com/prasn-/lambda/aws"
  version             = "1.2.0"
  lambda_name         = "ccop-compliance-rules-execution"
  lambda_description  = "a Lambda Function to perform lambda trigger operation"
  lambda_script_dir   = "./scripts/complianceRulesExecutionLambda/"
  lambda_handler      = "complianceRulesExecution.lambda_handler"
  lambda_role_arn     = module.lambda_ccop_compliance_rules_execution.iam_role_arn
  architectures       = ["x86_64"]
  memory_size         = 2048
  timeout             = 20
  runtime             = var.python_lambda_layer_runtime
  lambda_bucket_name  = local.lambda_bucket_name
  layers              = [aws_lambda_layer_version.advanced_python_wrapper_mysql[0].arn,local.splunk_layer_arn,aws_lambda_layer_version.otel[0].arn]

  vpc_config = {
    subnet_ids          = local.app_subnet_list
    security_group_ids  = ["${module.lambda_database_access_security_group.security_group_id}"]
  }

  logging_config = {
    log_format      = "Text"
    log_group_name  = "/application_logs"
  }

  environment = {
    s3_bucket                 = module.ccop_ingest_reporting_bucket.bucket_name
    db_host                   = module.aurora-mysql-ccops-cluster.rds_cluster_endpoint
    db_user                   = var.database_rw_user
    db_port                   = "3306"
    db_name                   = module.aurora-mysql-ccops-cluster.rds_cluster_database_name
    region                    = "us-east-2"
    dynamo_table              = module.ccop_dynamodb_table.dynamodb_table_id
    SPLUNK_REALM              = "us0"
    SPLUNK_ACCESS_TOKEN       = ""
    AWS_LAMBDA_EXEC_WRAPPER   = "/opt/otel-instrument"
    OTEL_SERVICE_NAME         = "Compliance Rules Execution Lambda"
    OTEL_RESOURCE_ATTRIBUTES  = "deployment.environment=dev"
    OTEL_PYTHON_LOG_CORRELATION = "true"
    PYTHONPATH                = "/opt/python/lib/python3.12/site-packages"
  }
}

##################################LAMBDA SPLUNK OBSERV TEST#############################################################
#########################################################################################################################
module "lambda_splunk_hello" {
  upload_to_s3        = true
  source              = "tfe.prasn.com/prasn-/lambda/aws"
  version             = "1.2.0"
  lambda_name         = "splunk-observ-hello"
  lambda_description  = "a Lambda Function Being used to test Splunk Observability OTEL Layer"
  lambda_script_dir   = "./scripts/SplunkHello/"
  lambda_handler      = "Hello.lambda_handler"
  lambda_role_arn     = module.splunk_observ_lambda_role.iam_role_arn
  architectures       = ["x86_64"]
  memory_size         = 2048
  timeout             = 20
  runtime             = var.otel_python_lambda_layer_runtime
  lambda_bucket_name  = local.lambda_bucket_name
  layers              = [ local.splunk_layer_arn, aws_lambda_layer_version.otel[0].arn ]

  vpc_config = {
    subnet_ids          = local.app_subnet_list
    security_group_ids  = ["${module.lambda_database_access_security_group.security_group_id}"]
  }

  logging_config = {
    log_format      = "Text"
    log_group_name  = "/application_logs"
  }

  environment = {
    SPLUNK_REALM               = "us0"
    SPLUNK_ACCESS_TOKEN        = ""
    AWS_LAMBDA_EXEC_WRAPPER    = "/opt/otel-instrument"
    OTEL_SERVICE_NAME          = "HelloSplunk"
    OTEL_RESOURCE_ATTRIBUTES   = "deployment.environment=dev"
    OTEL_PYTHON_LOG_CORRELATION = "true"
    PYTHONPATH                 = "/opt/python/lib/python3.12/site-packages"
  }
}