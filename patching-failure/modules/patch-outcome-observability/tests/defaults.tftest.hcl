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

run "default_shape_and_dormant" {
  command = plan
  assert {
    condition     = length(aws_iam_role.writer) == 0 && length(aws_iam_role_policy.archive) == 0 && output.central_prerequisites == null
    error_message = "Role reuse must not create a second identity/common policy or render unrelated central statements."
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
    condition     = aws_iam_role_policy.writer.name == "patch-outcome-us-east-1-runtime" && aws_iam_role_policy.writer.role == "patch-outcome-s3-writer"
    error_message = "Attach a regional policy to the existing role, including when its ARN has a path."
  }
  assert {
    condition     = aws_s3_bucket.lambda_package.bucket == "patch-outcome-pkg-222233334444-us-east-1"
    error_message = "The package bucket must be unique by account and region."
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/pilot-patch-outcome-us-east-1-writer"
    error_message = "The log group must include alias and region."
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365 && aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "Logs use explicit retention and no central key."
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
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "The package defaults to SSE-S3."
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
    condition     = output.writer_lambda_config.environment.BUCKET_NAME == var.archive_bucket_name && output.writer_lambda_config.environment.KMS_KEY_ARN == ""
    error_message = "Route archive settings to the handler."
  }
  assert {
    condition     = aws_lambda_function_event_invoke_config.this.maximum_retry_attempts == 2 && aws_lambda_function_event_invoke_config.this.maximum_event_age_in_seconds == 21600
    error_message = "Preserve async retries and age."
  }
}

run "actual_regional_policies_and_shared_resources" {
  command = apply
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.writer.policy).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
    error_message = "Validate actual generated log actions."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.writer.policy).Statement[0].Resource == ["${aws_cloudwatch_log_group.this.arn}:*"]
    error_message = "Limit log writes to this region/function."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.writer.policy).Statement[1].Resource == [module.lambda_dlq.queue_arn]
    error_message = "Grant sends only to the Lambda failure destination."
  }
  assert {
    condition     = toset(jsondecode(aws_sqs_queue_policy.target_dlq.policy).Statement[0].Condition.ArnEquals["aws:SourceArn"]) == toset(values(output.event_rule_arns))
    error_message = "Target policy must enumerate exactly the actual rule ARNs."
  }
  assert {
    condition     = jsondecode(aws_sqs_queue_policy.target_dlq.policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "222233334444"
    error_message = "Target policy must restrict the source account."
  }
  assert {
    condition     = module.writer_lambda.lambda_name == "pilot-patch-outcome-us-east-1-writer"
    error_message = "Check the name produced by the unchanged shared Lambda module."
  }
  assert {
    condition     = aws_lambda_function_event_invoke_config.this.destination_config[0].on_failure[0].destination == module.lambda_dlq.queue_arn
    error_message = "Wire the async failure destination."
  }
}

override_resource {
  target = aws_cloudwatch_event_rule.ssm["invocation_success"]
  values = { arn = "arn:aws:events:us-east-1:222233334444:rule/patch-outcome-invocation-success" }
}

override_resource {
  target = aws_cloudwatch_event_rule.ssm["invocation_failure"]
  values = { arn = "arn:aws:events:us-east-1:222233334444:rule/patch-outcome-invocation-failure" }
}

override_resource {
  target = aws_cloudwatch_event_rule.ssm["command_failure"]
  values = { arn = "arn:aws:events:us-east-1:222233334444:rule/patch-outcome-command-failure" }
}

override_resource {
  target = aws_cloudwatch_event_rule.canary[0]
  values = { arn = "arn:aws:events:us-east-1:222233334444:rule/patch-outcome-canary" }
}

override_resource {
  target = module.target_dlq.aws_sqs_queue.main
  values = { arn = "arn:aws:sqs:us-east-1:222233334444:pilot-patch-outcome-target-dlq" }
}

override_resource {
  target = module.lambda_dlq.aws_sqs_queue.main
  values = { arn = "arn:aws:sqs:us-east-1:222233334444:pilot-patch-outcome-lambda-dlq" }
}
