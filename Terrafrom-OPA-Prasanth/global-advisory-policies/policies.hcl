policy "advise_s3_module_usage" {
  query = "data.terraform.policies.aws_s3_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using S3 service module"
}

policy "advise_autoscaling_module_usage" {
  query = "data.terraform.policies.aws_autoscaling_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Autoscaling service module"
}

policy "advise_ecs_module_usage" {
  query = "data.terraform.policies.aws_ecs_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using ecs service module"
}

policy "advise_elb_module_usage" {
  query = "data.terraform.policies.aws_elb_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using ELB service module"
}

policy "advise_sns_module_usage" {
  query = "data.terraform.policies.aws_sns_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using SNS service module"
}

policy "advise_sqs_module_usage" {
  query = "data.terraform.policies.aws_sqs_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using SQS service module"
}

policy "advise_apigw_module_usage" {
  query = "data.terraform.policies.aws_apigw_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using API Gateway service module"
}

policy "advise_cognito_module_usage" {
  query = "data.terraform.policies.aws_cognito_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Cognito service module"
}

policy "advise_cloudwatch_module_usage" {
  query = "data.terraform.policies.aws_cloudwatch_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Cloudwatch service module"
}

policy "advise_ec2_module_usage" {
  query = "data.terraform.policies.aws_ec2_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using EC2 service module"
}

policy "advise_secrets_manager_module_usage" {
  query = "data.terraform.policies.aws_secrets_manager_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Secrets Manager service module"
}

policy "advise_cloudfront_module_usage" {
  query = "data.terraform.policies.aws_cloudfront_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using cloudfront service module"
}

policy "advise_elasticache_module_usage" {
  query = "data.terraform.policies.aws_elasticache_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Elasticache service module"
}

policy "advise_iam_module_usage" {
  query = "data.terraform.policies.aws_iam_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using IAM service module"
}

policy "advise_lambda_module_usage" {
  query = "data.terraform.policies.aws_lambda_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Lambda service module"
}

policy "advise_storagegw_module_usage" {
  query = "data.terraform.policies.aws_storagegw_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Storage gateway service module"
}

policy "advise_sfn_module_usage" {
  query = "data.terraform.policies.aws_sfn_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using Stepfunction service module"
}

policy "advise_waf_module_usage" {
  query = "data.terraform.policies.aws_waf_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using waf service module"
}

policy "advise_kms_module_usage" {
  query = "data.terraform.policies.aws_kms_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using kms service module"
}

policy "advise_ecr_module_usage" {
  query = "data.terraform.policies.aws_ecr_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using ecr service module"
}

policy "advise_redshift_module_usage" {
  query = "data.terraform.policies.aws_redshift_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using redshift service module"
}

policy "advise_redshiftserverless_module_usage" {
  query = "data.terraform.policies.aws_redshiftserverless_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using redshift serverless service module"
}

policy "advise_rds_module_usage" {
  query = "data.terraform.policies.aws_rds_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using rds service module"
}

policy "advise_rdsaurora_module_usage" {
  query = "data.terraform.policies.aws_rdsaurora_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using rds aurora service module"
}

policy "advise_dynamodb_module_usage" {
  query = "data.terraform.policies.aws_dynamodb_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using dynamodb service module"
}

policy "advise_rds_proxy_module_usage" {
  query = "data.terraform.policies.aws_rds_proxy_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using rds proxy service module"
}

policy "advise_efs_module_usage" {
  query = "data.terraform.policies.aws_efs_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using efs service module"
}

policy "advise_datasync_module_usage" {
  query = "data.terraform.policies.aws_datasync_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using datasync service module"
}

policy "advise_athena_module_usage" {
  query = "data.terraform.policies.aws_athena_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using athena service module"
}

policy "advise_transfer_family_module_usage" {
  query = "data.terraform.policies.aws_transfer_family_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using transfer family service module"
}

policy "advise_s3tables_module_usage" {
  query = "data.terraform.policies.aws_s3tables_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using S3 Tables service module"
}

policy "advise_apigwv2_module_usage" {
  query = "data.terraform.policies.aws_apigwv2_001_advise_module_usage.warn"
  enforcement_level = "advisory"
  description = "Warn not using API Gateway V2 service module"
}

policy "advise_ebs_encryption" {
  query = "data.terraform.policies.aws_ebs_001_advise_encryption.warn"
  enforcement_level = "advisory"
  description = "Warn EBS volumes and EC2 instances are not using encryption"
}