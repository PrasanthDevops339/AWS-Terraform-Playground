# Every guard rail in variables.tf, exercised. These runs are expected to fail
# variable validation -- expect_failures turns that into a passing test.

mock_provider "aws" {
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/patch-outcome-writer"
    }
  }
}

override_data {
  target = data.aws_iam_policy_document.assume
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}
override_data {
  target = data.aws_iam_policy_document.writer
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}
override_data {
  target = data.aws_iam_policy_document.target_dlq
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

variables {
  archive_bucket_name = "central-patching-logs-123456789012"
}

run "rejects_empty_bucket_name" {
  command = plan

  variables {
    archive_bucket_name = ""
  }

  expect_failures = [var.archive_bucket_name]
}

run "rejects_uppercase_name_prefix" {
  command = plan

  variables {
    name_prefix = "Patch-Outcome"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_writer_role_name_with_slash" {
  command = plan

  variables {
    writer_role_name = "team/patch-outcome-s3-writer"
  }

  expect_failures = [var.writer_role_name]
}

run "rejects_writer_role_name_with_wildcard" {
  command = plan

  variables {
    writer_role_name = "patch-outcome-*"
  }

  expect_failures = [var.writer_role_name]
}

run "rejects_prefix_with_leading_slash" {
  command = plan

  variables {
    archive_s3_prefix = "/patchingsolution-events/outcomes"
  }

  expect_failures = [var.archive_s3_prefix]
}

run "rejects_prefix_with_trailing_slash" {
  command = plan

  variables {
    archive_s3_prefix = "patchingsolution-events/outcomes/"
  }

  expect_failures = [var.archive_s3_prefix]
}

run "rejects_dropping_terminated_from_failure_statuses" {
  command = plan

  variables {
    invocation_failure_statuses = ["Failed", "TimedOut", "Cancelled", "Undeliverable"]
  }

  expect_failures = [var.invocation_failure_statuses]
}

run "rejects_non_cloudwatch_retention_value" {
  command = plan

  variables {
    lambda_log_retention_in_days = 45
  }

  expect_failures = [var.lambda_log_retention_in_days]
}

run "rejects_unknown_log_level" {
  command = plan

  variables {
    log_level = "TRACE"
  }

  expect_failures = [var.log_level]
}

run "rejects_iam_role_path_without_trailing_slash" {
  command = plan

  variables {
    iam_role_path = "/service-role"
  }

  expect_failures = [var.iam_role_path]
}
