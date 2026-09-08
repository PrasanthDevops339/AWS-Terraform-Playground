mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "222233334444" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_iam_account_alias" { defaults = { account_alias = "pilot" } }
  mock_resource "aws_lambda_function" { defaults = { arn = "arn:aws:lambda:us-east-1:222233334444:function:pilot-patch-outcome-us-east-1-writer" } }
  mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:222233334444:log-group:/aws/lambda/pilot-patch-outcome-us-east-1-writer" } }
  mock_resource "aws_sqs_queue" { defaults = { arn = "arn:aws:sqs:us-east-1:222233334444:mock-queue" } }
  mock_resource "aws_cloudwatch_event_rule" { defaults = { arn = "arn:aws:events:us-east-1:222233334444:rule/mock-rule" } }
}
variables {
  create_writer_role  = false
  archive_bucket_name = "central-patching-logs-111122223333"
  writer_role_arn     = "arn:aws:iam::222233334444:role/platform/patch-outcome-s3-writer"
}

run "arm_rules" {
  command = plan
  variables {
    rules_enabled = true
  }
  assert {
    condition     = alltrue([for r in aws_cloudwatch_event_rule.ssm : r.state == "ENABLED"])
    error_message = "Explicitly arm all three rules."
  }
}

run "canary_off" {
  command = plan
  variables {
    enable_canary = false
  }
  assert {
    condition     = length(aws_cloudwatch_event_rule.canary) == 0 && length(aws_cloudwatch_event_target.canary) == 0 && output.canary_command == null
    error_message = "Disabling the optional canary removes it."
  }
}

run "archive_kms_and_acl" {
  command = plan
  variables {
    archive_kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    archive_object_acl  = "bucket-owner-full-control"
  }
  assert {
    condition     = output.writer_lambda_config.environment.KMS_KEY_ARN == var.archive_kms_key_arn && output.writer_lambda_config.environment.OBJECT_ACL == "bucket-owner-full-control"
    error_message = "Pass the archive CMK and ACL to the handler."
  }
}

run "enrichment_off" {
  command = plan
  variables {
    enable_enrichment     = false
    include_instance_tags = false
  }
  assert {
    condition     = output.writer_lambda_config.environment.ENRICH == "false" && output.writer_lambda_config.environment.INCLUDE_INSTANCE_TAGS == "false"
    error_message = "Pass both enrichment flags."
  }
}

run "log_key_does_not_encrypt_packages" {
  command = plan
  variables {
    local_kms_key_arn = "arn:aws:kms:us-east-1:222233334444:key/00000000-0000-0000-0000-000000000000"
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == var.local_kms_key_arn && one(aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "A log-specific key must not be reused for the package bucket."
  }
}

run "independent_package_key" {
  command = plan
  variables {
    lambda_package_kms_key_arn = "arn:aws:kms:us-east-1:222233334444:key/00000000-0000-0000-0000-000000000000"
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == null && one(aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.lambda_package_kms_key_arn
    error_message = "The package key is independent of log encryption."
  }
}

run "name_prefix_and_concurrency" {
  command = plan
  variables {
    name_prefix          = "px-test"
    reserved_concurrency = 5
  }
  assert {
    condition     = aws_s3_bucket.lambda_package.bucket == "px-test-pkg-222233334444-us-east-1" && aws_cloudwatch_log_group.this.name == "/aws/lambda/pilot-px-test-us-east-1-writer" && output.writer_lambda_config.reserved_concurrent_executions == 5
    error_message = "Derive regional names and pass explicit concurrency."
  }
}
