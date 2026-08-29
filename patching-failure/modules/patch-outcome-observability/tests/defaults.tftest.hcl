# Shape and wiring assertions for the module under its default inputs.
#
# All runs use command = plan with a mocked AWS provider -- free, offline, no
# credentials. The archive provider is left real: it actually zips src/, which
# is what the shared terraform-aws-lambda module packages and hashes.
#
# Assertions only touch attributes that come from configuration (literals,
# variable-derived values, or references). A mock provider fills computed
# attributes -- ARNs, generated names, the account alias -- with junk, so those
# are matched with strcontains() on the parts we control, never compared whole.

mock_provider "aws" {}

# account_id / partition / region feed resource names and ARNs; pin them so
# those are known at plan. The account alias (looked up in this module and in
# both shared sqs/lambda modules) prefixes every generated name.
override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}
override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}
override_data {
  target = data.aws_region.current
  values = { region = "us-east-1" }
}
override_data {
  target = data.aws_iam_account_alias.current
  values = { account_alias = "acme-test" }
}
override_data {
  target = module.writer_lambda.data.aws_iam_account_alias.current
  values = { account_alias = "acme-test" }
}
override_data {
  target = module.target_dlq.data.aws_iam_account_alias.current
  values = { account_alias = "acme-test" }
}
override_data {
  target = module.lambda_dlq.data.aws_iam_account_alias.current
  values = { account_alias = "acme-test" }
}

# aws_iam_policy_document is provider-computed; a mock provider returns a
# non-JSON string that aws_iam_role / aws_sqs_queue_policy then reject.
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
  archive_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

run "default_plan_is_valid" {
  command = plan
}

run "three_ssm_rules_plus_canary" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.ssm) == 3
    error_message = "expected exactly three SSM EventBridge rules"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.canary) == 1
    error_message = "canary rule should be created when enable_canary is true (default)"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.ssm) == 3 && length(aws_cloudwatch_event_target.canary) == 1
    error_message = "every rule needs a target"
  }

  # allowed_triggers is built 1:1 from these rules, so the rule set is the
  # permission set (the shared module doesn't export its permission resources).
  assert {
    condition     = length(output.event_rule_arns) == 4
    error_message = "expected 4 rules (3 SSM + canary), each of which yields one Lambda permission"
  }
}

run "ssm_rule_patterns_are_scoped_to_runpatchbaseline" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_cloudwatch_event_rule.ssm : strcontains(r.event_pattern, "AWS-RunPatchBaseline")])
    error_message = "every SSM rule pattern must prefix-match AWS-RunPatchBaseline"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_event_rule.ssm["invocation_failure"].event_pattern, "Terminated")
    error_message = "the invocation_failure pattern must include the Terminated status"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_event_rule.canary[0].event_pattern, "custom.patch-canary")
    error_message = "the canary rule must match source custom.patch-canary"
  }
}

run "rules_enabled_true_by_default" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_cloudwatch_event_rule.ssm : r.state == "ENABLED"])
    error_message = "SSM rules should be ENABLED when rules_enabled is true"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.canary[0].state == "ENABLED"
    error_message = "canary rule is always ENABLED"
  }
}

run "lambda_contract" {
  command = plan

  assert {
    condition     = module.writer_lambda.lambda_config.runtime == "python3.13"
    error_message = "Lambda runtime must be python3.13"
  }

  assert {
    condition     = module.writer_lambda.lambda_config.handler == "handler.handler"
    error_message = "Lambda handler must be handler.handler"
  }

  assert {
    condition     = module.writer_lambda.lambda_config.timeout == 30 && module.writer_lambda.lambda_config.memory_size == 128
    error_message = "Lambda must be 128 MB / 30 s"
  }

  assert {
    condition     = module.writer_lambda.lambda_config.package_type == "Zip"
    error_message = "Lambda must be a Zip package"
  }

  assert {
    condition     = module.writer_lambda.lambda_config.environment["BUCKET_NAME"] == var.archive_bucket_name
    error_message = "BUCKET_NAME env var must be the archive bucket"
  }

  assert {
    condition     = module.writer_lambda.lambda_config.environment["S3_PREFIX"] == "patchingsolution-events/outcomes"
    error_message = "S3_PREFIX env var must default to the sibling outcomes prefix"
  }

  # module.writer_lambda.lambda_name is aws_lambda_function.function_name, an
  # Optional+Computed attribute the mock provider marks unknown at plan. The
  # naming intent is covered by the log group name assertion below, which is
  # built from this module's own local.function_name.
  assert {
    condition     = aws_lambda_function_event_invoke_config.this.maximum_retry_attempts == 2
    error_message = "async invoke config must retry twice before dead-lettering"
  }

  assert {
    condition     = length(aws_lambda_function_event_invoke_config.this.destination_config[0].on_failure) == 1
    error_message = "an async on_failure destination must be configured"
  }
}

run "lambda_package_bucket_is_locked_down" {
  command = plan

  assert {
    condition     = aws_s3_bucket.lambda_package.bucket == "patch-outcome-pkg-123456789012"
    error_message = "package bucket name must be name_prefix-pkg-<account-id>"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.lambda_package.block_public_acls && aws_s3_bucket_public_access_block.lambda_package.block_public_policy && aws_s3_bucket_public_access_block.lambda_package.ignore_public_acls && aws_s3_bucket_public_access_block.lambda_package.restrict_public_buckets
    error_message = "the package bucket must block all public access"
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.lambda_package.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "the package bucket must enforce bucket-owner ownership"
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule :
      r.apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    ])
    error_message = "the package bucket must be SSE-S3 encrypted by default"
  }
}

run "writer_role_name_is_pinned_not_derived" {
  command = plan

  assert {
    condition     = aws_iam_role.writer.name == "patch-outcome-s3-writer"
    error_message = "writer role name must be the exact fleet-wide default, not derived from name_prefix"
  }
}

run "dlqs_are_named_from_the_name_prefix" {
  command = plan

  # message_retention_seconds (1209600) and the absence of a KMS key are passed
  # as literals into the shared terraform-aws-sqs module calls in main.tf; the
  # module exposes neither as an output, so they are covered by `validate`
  # parsing the literal, not asserted here.
  assert {
    condition     = strcontains(module.target_dlq.queue_name, "patch-outcome-target-dlq") && strcontains(module.lambda_dlq.queue_name, "patch-outcome-lambda-dlq")
    error_message = "DLQ names must carry the name_prefix-derived suffix"
  }

  assert {
    condition     = module.target_dlq.secure_transport_policy_enabled == false
    error_message = "the shared module's canned TLS-deny policy must be off (we attach the EventBridge allow-policy instead)"
  }
}

run "log_group_retention_and_no_central_key" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "log group must not be encrypted with the central archive key by default"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "default log retention must be 365 days"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_log_group.this.name, "/aws/lambda/") && strcontains(aws_cloudwatch_log_group.this.name, "patch-outcome-writer")
    error_message = "log group name must match the (alias-prefixed) function name"
  }
}

run "renders_central_prerequisites_output" {
  command = plan

  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Action == "s3:PutObject"
    error_message = "bucket policy statement must grant exactly s3:PutObject"
  }

  assert {
    condition = toset(output.central_prerequisites.kms_key_policy_statement.Action) == toset([
      "kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"
    ])
    error_message = "KMS key policy statement must grant only the three encrypt-only actions (no kms:Decrypt)"
  }

  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Condition.StringEquals["aws:PrincipalOrgID"] != null
    error_message = "bucket policy statement must be scoped by aws:PrincipalOrgID"
  }
}
