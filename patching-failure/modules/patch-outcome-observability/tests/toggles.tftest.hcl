# Behaviour of the module's feature flags: dormant deploy, canary off,
# enrichment/tags off, KMS key routing, name_prefix derivation.
#
# Assertions stay on configuration-derived attributes (see defaults.tftest.hcl).
# The inline IAM policy JSON is provider-computed and cannot be introspected
# under a mock provider, so KMS / EC2 grants are checked indirectly through the
# Lambda environment variables that gate the same behaviour in the handler.

mock_provider "aws" {}

# See defaults.tftest.hcl for why each of these is pinned.
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

run "dormant_disables_ssm_rules_but_not_the_canary" {
  command = plan

  variables {
    rules_enabled = false
  }

  assert {
    condition     = alltrue([for r in aws_cloudwatch_event_rule.ssm : r.state == "DISABLED"])
    error_message = "rules_enabled = false must set every SSM rule to DISABLED"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.canary[0].state == "ENABLED"
    error_message = "the canary must stay ENABLED even when the module is dormant"
  }
}

run "canary_can_be_turned_off_entirely" {
  command = plan

  variables {
    enable_canary = false
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.canary) == 0
    error_message = "enable_canary = false must create no canary rule"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.canary) == 0
    error_message = "enable_canary = false must create no canary target"
  }

  assert {
    condition     = length(output.event_rule_arns) == 3
    error_message = "enable_canary = false must leave only the three SSM rules (hence three Lambda permissions)"
  }

  assert {
    condition     = !contains(keys(output.event_rule_arns), "canary")
    error_message = "event_rule_arns must not carry a canary entry when the canary is disabled"
  }

  assert {
    condition     = output.canary_command == null
    error_message = "canary_command output must be null when the canary is disabled"
  }
}

run "kms_key_set_flows_into_the_lambda_env" {
  command = plan

  variables {
    archive_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = output.writer_lambda_config.environment["KMS_KEY_ARN"] == "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"
    error_message = "archive_kms_key_arn must be passed to the handler as KMS_KEY_ARN"
  }
}

run "enrichment_and_tag_toggles_reach_the_handler" {
  command = plan

  variables {
    enable_enrichment     = false
    include_instance_tags = false
  }

  assert {
    condition     = output.writer_lambda_config.environment["ENRICH"] == "false"
    error_message = "enable_enrichment = false must set ENRICH=false"
  }

  assert {
    condition     = output.writer_lambda_config.environment["INCLUDE_INSTANCE_TAGS"] == "false"
    error_message = "include_instance_tags = false must set INCLUDE_INSTANCE_TAGS=false"
  }
}

run "local_kms_key_encrypts_log_group_and_package_bucket" {
  command = plan

  variables {
    local_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/22222222-2222-2222-2222-222222222222"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/22222222-2222-2222-2222-222222222222"
    error_message = "local_kms_key_arn must encrypt the Lambda log group"
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_server_side_encryption_configuration.lambda_package.rule :
      r.apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    ])
    error_message = "local_kms_key_arn must switch the package bucket to SSE-KMS"
  }
}

run "reserved_concurrency_passes_through_when_set" {
  command = plan

  variables {
    reserved_concurrency = 5
  }

  assert {
    condition     = output.writer_lambda_config.reserved_concurrent_executions == 5
    error_message = "reserved_concurrency must pass through to the function when set"
  }
}

run "name_prefix_drives_every_derived_name" {
  command = plan

  variables {
    name_prefix = "px-test"
  }

  assert {
    condition     = strcontains(module.target_dlq.queue_name, "px-test-target-dlq") && strcontains(module.lambda_dlq.queue_name, "px-test-lambda-dlq")
    error_message = "DLQ names must be name_prefix-derived"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.ssm["invocation_success"].name == "px-test-invocation-success"
    error_message = "SSM rule names must be name_prefix-derived with underscores replaced by hyphens"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.canary[0].name == "px-test-canary"
    error_message = "canary rule name must be name_prefix-derived"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_log_group.this.name, "px-test-writer")
    error_message = "log group (built from local.function_name) must carry the name_prefix-writer suffix"
  }

  assert {
    condition     = aws_s3_bucket.lambda_package.bucket == "px-test-pkg-123456789012"
    error_message = "package bucket name must be name_prefix-pkg-<account-id>"
  }

  # writer_role_name is deliberately NOT tied to name_prefix.
  assert {
    condition     = aws_iam_role.writer.name == "patch-outcome-s3-writer"
    error_message = "writer role name must stay the fleet-wide constant regardless of name_prefix"
  }
}
