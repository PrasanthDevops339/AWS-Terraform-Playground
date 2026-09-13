# Offline tests: every AWS call is mocked. The archive provider runs locally
# and writes the package zip to the working directory (gitignored).
mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "222233334444" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_iam_account_alias" { defaults = { account_alias = "pilot" } }
  mock_data "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:222233334444:log-group:app_log/" } }
  mock_resource "aws_lambda_function" { defaults = { arn = "arn:aws:lambda:us-east-1:222233334444:function:pilot-patch-outcome-us-east-1-writer" } }
  mock_resource "aws_cloudwatch_event_rule" { defaults = { arn = "arn:aws:events:us-east-1:222233334444:rule/mock-rule" } }
}

variables {
  account_id                 = "222233334444"
  organization_id            = "o-example1234"
  archive_bucket_name        = "central-patching-logs-111122223333"
  archive_kms_key_arn        = "arn:aws:kms:us-east-2:111122223333:key/11111111-1111-1111-1111-111111111111"
  lambda_package_kms_key_arn = "arn:aws:kms:us-east-1:222233334444:key/22222222-2222-2222-2222-222222222222"
}

# ---------------------------------------------------------------------------
# Default shape: basic path, dormant rules, no DLQ, KMS everywhere, app_log/
# ---------------------------------------------------------------------------

run "default_shape_and_dormant" {
  command = plan
  assert {
    condition     = aws_iam_role.writer.name == "patch-outcome-s3-writer" && output.writer_role_arn == "arn:aws:iam::222233334444:role/patch-outcome-s3-writer"
    error_message = "Create the fixed-name writer role."
  }
  assert {
    condition     = jsondecode(aws_iam_role.writer.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    error_message = "Only Lambda assumes the role."
  }
  assert {
    condition     = length(aws_cloudwatch_event_rule.ssm) == 3 && length(aws_cloudwatch_event_rule.canary) == 1
    error_message = "Three SSM rules and a canary are required."
  }
  assert {
    condition     = length(aws_cloudwatch_event_target.ssm) == 3 && length(aws_cloudwatch_event_target.canary) == 1
    error_message = "Every rule must have a target."
  }
  assert {
    condition     = alltrue([for r in aws_cloudwatch_event_rule.ssm : r.state == "DISABLED"]) && aws_cloudwatch_event_rule.canary[0].state == "ENABLED"
    error_message = "Default deployments must be dormant with a live canary."
  }
  assert {
    condition     = alltrue([for t in concat(values(aws_cloudwatch_event_target.ssm), aws_cloudwatch_event_target.canary) : length(t.dead_letter_config) == 0])
    error_message = "Basic path: event targets must not reference the disabled DLQ."
  }
  assert {
    condition     = length(aws_lambda_function_event_invoke_config.this.destination_config) == 0
    error_message = "Basic path: no async failure destination."
  }
  assert {
    condition     = aws_lambda_function_event_invoke_config.this.maximum_retry_attempts == 2 && aws_lambda_function_event_invoke_config.this.maximum_event_age_in_seconds == 21600
    error_message = "Preserve async retries and age."
  }
  assert {
    condition     = aws_s3_bucket.lambda_package.bucket == "patch-outcome-pkg-222233334444-us-east-1"
    error_message = "The package bucket must be unique by account and region."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.lambda_package.block_public_acls && aws_s3_bucket_public_access_block.lambda_package.block_public_policy && aws_s3_bucket_public_access_block.lambda_package.ignore_public_acls && aws_s3_bucket_public_access_block.lambda_package.restrict_public_buckets
    error_message = "Block all package bucket public access."
  }
  assert {
    condition     = aws_s3_bucket_ownership_controls.lambda_package.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Package ownership must be enforced."
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms" && one(aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.lambda_package_kms_key_arn && one(aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule).bucket_key_enabled
    error_message = "The package bucket must use SSE-KMS with the supplied CMK and a bucket key."
  }
  assert {
    condition     = output.writer_lambda_config.logging_config.log_group == "app_log/" && output.writer_lambda_config.logging_config.log_format == "Text" && output.lambda_log_group_name == "app_log/"
    error_message = "The Lambda must log to the existing app_log/ group in Text format."
  }
  assert {
    condition     = output.writer_lambda_config.runtime == "python3.13" && output.writer_lambda_config.handler == "handler.handler" && output.writer_lambda_config.package_type == "Zip"
    error_message = "Retain the shared Lambda input contract."
  }
  assert {
    condition     = output.writer_lambda_config.timeout == 30 && output.writer_lambda_config.memory_size == 128 && output.writer_lambda_config.reserved_concurrent_executions == -1
    error_message = "Retain sizing and unreserved concurrency."
  }
  assert {
    condition     = output.writer_lambda_config.environment.BUCKET_NAME == var.archive_bucket_name && output.writer_lambda_config.environment.KMS_KEY_ARN == var.archive_kms_key_arn && output.writer_lambda_config.environment.OBJECT_ACL == ""
    error_message = "Route archive bucket and central CMK to the handler."
  }
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.archive.policy).Statement) == 4
    error_message = "Archive policy has S3, KMS, SSM and EC2 statements by default."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.archive.policy).Statement[0].Action == ["s3:PutObject"] && jsondecode(aws_iam_role_policy.archive.policy).Statement[0].Resource == ["arn:aws:s3:::central-patching-logs-111122223333/patchingsolution-events/outcomes/*"]
    error_message = "Write-only archive access to the outcomes prefix."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.archive.policy).Statement[1].Resource == [var.archive_kms_key_arn] && !contains(jsondecode(aws_iam_role_policy.archive.policy).Statement[1].Action, "kms:Decrypt")
    error_message = "Only the central key receives encrypt permissions; no Decrypt."
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.archive.policy).Statement[2].Action) == toset(["ssm:ListCommandInvocations", "ssm:ListCommands", "ssm:DescribeInstanceInformation"])
    error_message = "Use aggregate invocation read access, not plugin API access."
  }
  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Condition.StringEquals["aws:PrincipalOrgID"] == "o-example1234" && output.central_prerequisites.kms_key_policy_statement != null
    error_message = "Resolve the org ID and always render the KMS statement."
  }
  assert {
    condition     = !contains(output.central_prerequisites.kms_key_policy_statement.Action, "kms:Decrypt")
    error_message = "The central KMS statement grants no Decrypt."
  }
}

run "event_patterns_match_fixtures" {
  command = plan
  assert {
    condition = alltrue([
      for fixture in jsondecode(file("${path.module}/tests/fixtures/event-patterns.json")) :
      toset(fixture.expected) == toset(concat(
        [for key, rule in aws_cloudwatch_event_rule.ssm : key if
          contains(jsondecode(rule.event_pattern).source, fixture.event.source) &&
          contains(jsondecode(rule.event_pattern)["detail-type"], fixture.event["detail-type"]) &&
          startswith(try(fixture.event.detail["document-name"], ""), jsondecode(rule.event_pattern).detail["document-name"][0].prefix) &&
          contains(jsondecode(rule.event_pattern).detail.status, try(fixture.event.detail.status, ""))
        ],
        contains(jsondecode(aws_cloudwatch_event_rule.canary[0].event_pattern).source, fixture.event.source) &&
        contains(jsondecode(aws_cloudwatch_event_rule.canary[0].event_pattern)["detail-type"], fixture.event["detail-type"]) ? ["canary"] : []
      ))
    ])
    error_message = "A representative SSM/non-SSM event matches the wrong generated rule."
  }
}

run "applied_runtime_policy_basic_path" {
  command = apply
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.runtime.policy).Statement) == 1
    error_message = "Basic path: the runtime policy grants logs only (no SQS)."
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.runtime.policy).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && jsondecode(aws_iam_role_policy.runtime.policy).Statement[0].Resource == ["arn:aws:logs:us-east-1:222233334444:log-group:app_log/:*"]
    error_message = "Limit log writes to streams in the existing app_log/ group."
  }
  assert {
    condition     = aws_iam_role_policy.runtime.role == aws_iam_role.writer.name && aws_iam_role_policy.archive.role == aws_iam_role.writer.name
    error_message = "Both policies attach to the created execution role."
  }
  assert {
    condition     = module.writer_lambda.lambda_name == "pilot-patch-outcome-us-east-1-writer"
    error_message = "Check the name produced by the unchanged shared Lambda module."
  }
}

# ---------------------------------------------------------------------------
# Toggles
# ---------------------------------------------------------------------------

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

run "path_boundary_and_acl" {
  command = plan
  variables {
    iam_role_path            = "/platform/"
    permissions_boundary_arn = "arn:aws:iam::222233334444:policy/boundary"
    archive_object_acl       = "bucket-owner-full-control"
  }
  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Condition.ArnLike["aws:PrincipalArn"] == "arn:aws:iam::*:role/platform/patch-outcome-s3-writer" && output.central_prerequisites.kms_key_policy_statement.Condition.ArnLike["aws:PrincipalArn"] == "arn:aws:iam::*:role/platform/patch-outcome-s3-writer"
    error_message = "Both central statements must match the full role path."
  }
  assert {
    condition     = aws_iam_role.writer.permissions_boundary == var.permissions_boundary_arn
    error_message = "Pass the permissions boundary."
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.archive.policy).Statement[0].Action) == toset(["s3:PutObject", "s3:PutObjectAcl"]) && output.central_prerequisites.bucket_policy_statement.Condition.StringEquals["s3:x-amz-acl"] == "bucket-owner-full-control"
    error_message = "Both sides grant and require the ACL only when requested."
  }
  assert {
    condition     = output.writer_lambda_config.environment.OBJECT_ACL == "bucket-owner-full-control"
    error_message = "Pass the ACL to the handler."
  }
}

run "no_enrichment" {
  command = plan
  variables {
    enable_enrichment     = false
    include_instance_tags = false
  }
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.archive.policy).Statement) == 2 && output.writer_lambda_config.environment.ENRICH == "false" && output.writer_lambda_config.environment.INCLUDE_INSTANCE_TAGS == "false"
    error_message = "Disable all enrichment permissions and flags together (S3 + KMS remain)."
  }
}

run "no_tag_permissions" {
  command = plan
  variables {
    include_instance_tags = false
  }
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.archive.policy).Statement) == 3
    error_message = "Keep S3, KMS and SSM but remove EC2 when tags are off."
  }
}

run "custom_log_group" {
  command = plan
  variables {
    app_log_group_name = "app_log/patching"
  }
  assert {
    condition     = output.writer_lambda_config.logging_config.log_group == "app_log/patching"
    error_message = "Pass the configured existing log group to the Lambda."
  }
}

run "name_prefix_and_concurrency" {
  command = plan
  variables {
    name_prefix          = "px-test"
    reserved_concurrency = 5
  }
  assert {
    condition     = aws_s3_bucket.lambda_package.bucket == "px-test-pkg-222233334444-us-east-1" && output.writer_lambda_config.reserved_concurrent_executions == 5
    error_message = "Derive names and pass explicit concurrency."
  }
}

# ---------------------------------------------------------------------------
# Validation and preconditions
# ---------------------------------------------------------------------------

run "rejects_bad_account_id" {
  command = plan
  variables {
    account_id = "1234"
  }
  expect_failures = [var.account_id]
}

run "rejects_placeholder_org" {
  command = plan
  variables {
    organization_id = "o-xxxxxxxxxx"
  }
  expect_failures = [var.organization_id]
}

run "rejects_empty_bucket" {
  command = plan
  variables {
    archive_bucket_name = ""
  }
  expect_failures = [var.archive_bucket_name]
}

run "rejects_empty_archive_key" {
  command = plan
  variables {
    archive_kms_key_arn = ""
  }
  expect_failures = [var.archive_kms_key_arn]
}

run "rejects_alias_archive_key" {
  command = plan
  variables {
    archive_kms_key_arn = "arn:aws:kms:us-east-2:111122223333:alias/central-archive"
  }
  expect_failures = [var.archive_kms_key_arn]
}

run "rejects_empty_package_key" {
  command = plan
  variables {
    lambda_package_kms_key_arn = ""
  }
  expect_failures = [var.lambda_package_kms_key_arn]
}

run "rejects_other_region_package_key" {
  command = plan
  variables {
    lambda_package_kms_key_arn = "arn:aws:kms:us-west-2:222233334444:key/test"
  }
  expect_failures = [aws_s3_bucket.lambda_package]
}

run "rejects_empty_log_group" {
  command = plan
  variables {
    app_log_group_name = ""
  }
  expect_failures = [var.app_log_group_name]
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

run "rejects_missing_terminated" {
  command = plan
  variables {
    invocation_failure_statuses = ["Failed"]
  }
  expect_failures = [var.invocation_failure_statuses]
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

run "rejects_role_slash" {
  command = plan
  variables {
    writer_role_name = "team/writer"
  }
  expect_failures = [var.writer_role_name]
}

run "rejects_bad_path" {
  command = plan
  variables {
    iam_role_path = "/platform"
  }
  expect_failures = [var.iam_role_path]
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
