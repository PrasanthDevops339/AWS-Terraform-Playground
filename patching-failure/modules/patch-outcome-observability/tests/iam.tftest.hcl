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
  archive_bucket_name = "central-patching-logs-111122223333"
  organization_id     = "o-example1234"
}

run "included_role_policy_and_central_output" {
  command = plan
  assert {
    condition     = aws_iam_role.writer[0].name == "patch-outcome-s3-writer" && output.writer_role_arn == "arn:aws:iam::222233334444:role/patch-outcome-s3-writer"
    error_message = "Create the fixed-name writer role once."
  }
  assert {
    condition     = jsondecode(aws_iam_role.writer[0].assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    error_message = "Only Lambda assumes the role."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.archive[0].policy).Statement[0].Action == ["s3:PutObject"] && jsondecode(aws_iam_role_policy.archive[0].policy).Statement[0].Resource == ["arn:aws:s3:::central-patching-logs-111122223333/patchingsolution-events/outcomes/*"]
    error_message = "Inspect real IAM JSON for write-only archive access."
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.archive[0].policy).Statement[1].Action) == toset(["ssm:ListCommandInvocations", "ssm:ListCommands", "ssm:DescribeInstanceInformation"])
    error_message = "Use aggregate invocation read access, not plugin API access."
  }
  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Condition.StringEquals["aws:PrincipalOrgID"] == "o-example1234" && output.central_prerequisites.kms_key_policy_statement == null
    error_message = "Resolve the org ID and omit KMS policy for SSE-S3."
  }
}

run "path_boundary_acl_and_kms" {
  command = plan
  variables {
    iam_role_path            = "/platform/"
    permissions_boundary_arn = "arn:aws:iam::222233334444:policy/boundary"
    archive_object_acl       = "bucket-owner-full-control"
    archive_kms_key_arn      = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  }
  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Condition.ArnLike["aws:PrincipalArn"] == "arn:aws:iam::*:role/platform/patch-outcome-s3-writer" && output.central_prerequisites.kms_key_policy_statement.Condition.ArnLike["aws:PrincipalArn"] == "arn:aws:iam::*:role/platform/patch-outcome-s3-writer"
    error_message = "Both central statements must match the full role path."
  }
  assert {
    condition     = aws_iam_role.writer[0].permissions_boundary == var.permissions_boundary_arn
    error_message = "Pass the account boundary."
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.archive[0].policy).Statement[0].Action) == toset(["s3:PutObject", "s3:PutObjectAcl"]) && toset(output.central_prerequisites.bucket_policy_statement.Action) == toset(["s3:PutObject", "s3:PutObjectAcl"])
    error_message = "Both sides grant ACL writes only when requested."
  }
  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Condition.StringEquals["s3:x-amz-acl"] == "bucket-owner-full-control"
    error_message = "Require the requested ACL on central writes."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.archive[0].policy).Statement[1].Resource == [var.archive_kms_key_arn] && !contains(output.central_prerequisites.kms_key_policy_statement.Action, "kms:Decrypt")
    error_message = "Only the selected central key receives write permissions."
  }
}

run "no_enrichment_permissions" {
  command = plan
  variables {
    enable_enrichment = false
  }
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.archive[0].policy).Statement) == 1
    error_message = "Disable all enrichment permissions together."
  }
}

run "no_tag_permissions" {
  command = plan
  variables {
    include_instance_tags = false
  }
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.archive[0].policy).Statement) == 2
    error_message = "Keep SSM but remove EC2 when tags are off."
  }
}

run "rejects_placeholder_org" {
  command = plan
  variables {
    organization_id = "o-xxxxxxxxxx"
  }
  expect_failures = [var.organization_id]
}

run "rejects_bad_org" {
  command = plan
  variables {
    organization_id = "bad"
  }
  expect_failures = [var.organization_id]
}

run "rejects_role_slash" {
  command = plan
  variables {
    writer_role_name = "team/writer"
  }
  expect_failures = [var.writer_role_name]
}

run "rejects_role_wildcard" {
  command = plan
  variables {
    writer_role_name = "writer*"
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

run "rejects_wildcard_path" {
  command = plan
  variables {
    iam_role_path = "/team*/"
  }
  expect_failures = [var.iam_role_path]
}

run "rejects_acl" {
  command = plan
  variables {
    archive_object_acl = "public-read"
  }
  expect_failures = [var.archive_object_acl]
}

run "included_role_is_used_by_lambda" {
  command = apply
  assert {
    condition     = length(aws_iam_role.writer) == 1 && length(aws_iam_role_policy.archive) == 1
    error_message = "The default Lambda deployment must own one role and one common permissions policy."
  }
  assert {
    condition     = aws_iam_role_policy.writer.role == aws_iam_role.writer[0].name && aws_iam_role_policy.archive[0].role == aws_iam_role.writer[0].id
    error_message = "Common and regional permissions must attach to the created execution role."
  }
}

run "rejects_missing_organization" {
  command = plan
  variables {
    organization_id = null
  }
  expect_failures = [var.organization_id]
}

run "rejects_create_with_existing_arn" {
  command = plan
  variables {
    writer_role_arn = "arn:aws:iam::222233334444:role/patch-outcome-s3-writer"
  }
  expect_failures = [var.writer_role_arn]
}
