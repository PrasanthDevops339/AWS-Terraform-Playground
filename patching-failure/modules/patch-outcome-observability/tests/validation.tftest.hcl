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

run "rejects_empty_bucket" {
  command = plan
  variables {
    archive_bucket_name = ""
  }
  expect_failures = [var.archive_bucket_name]
}

run "rejects_uppercase_prefix" {
  command = plan
  variables {
    name_prefix = "Bad"
  }
  expect_failures = [var.name_prefix]
}

run "rejects_prefix_slash" {
  command = plan
  variables {
    archive_s3_prefix = "/outcomes"
  }
  expect_failures = [var.archive_s3_prefix]
}

run "rejects_prefix_trailing_slash" {
  command = plan
  variables {
    archive_s3_prefix = "outcomes/"
  }
  expect_failures = [var.archive_s3_prefix]
}

run "rejects_prefix_wildcard" {
  command = plan
  variables {
    archive_s3_prefix = "outcomes*"
  }
  expect_failures = [var.archive_s3_prefix]
}

run "rejects_missing_terminated" {
  command = plan
  variables {
    invocation_failure_statuses = ["Failed"]
  }
  expect_failures = [var.invocation_failure_statuses]
}

run "rejects_retention" {
  command = plan
  variables {
    lambda_log_retention_in_days = 45
  }
  expect_failures = [var.lambda_log_retention_in_days]
}

run "rejects_log_level" {
  command = plan
  variables {
    log_level = "TRACE"
  }
  expect_failures = [var.log_level]
}

run "rejects_acl" {
  command = plan
  variables {
    archive_object_acl = "public-read"
  }
  expect_failures = [var.archive_object_acl]
}

run "rejects_role_arn" {
  command = plan
  variables {
    writer_role_arn = "not-an-arn"
  }
  expect_failures = [var.writer_role_arn]
}

run "rejects_other_account_role" {
  command = plan
  variables {
    writer_role_arn = "arn:aws:iam::333344445555:role/writer"
  }
  expect_failures = [aws_s3_bucket.lambda_package]
}

run "rejects_other_region_key" {
  command = plan
  variables {
    lambda_package_kms_key_arn = "arn:aws:kms:us-west-2:222233334444:key/test"
  }
  expect_failures = [aws_s3_bucket.lambda_package]
}

run "rejects_long_bucket" {
  command = plan
  variables {
    name_prefix = "abcdefghijklmnopqrstuvwxyzabcdefghijklmno"
  }
  expect_failures = [aws_s3_bucket.lambda_package]
}

run "rejects_long_alias" {
  command = plan
  override_data {
    target = data.aws_iam_account_alias.current
    values = { account_alias = "this-account-alias-is-too-long-for-the-derived-function-name" }
  }
  expect_failures = [aws_s3_bucket.lambda_package]
}

run "rejects_reuse_without_role" {
  command = plan
  variables {
    writer_role_arn = null
  }
  expect_failures = [var.writer_role_arn]
}
