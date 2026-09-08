# Separate test file/state models a separate AFT member execution.
mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "333344445555" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_iam_account_alias" { defaults = { account_alias = "pilot" } }
  mock_resource "aws_lambda_function" { defaults = { arn = "arn:aws:lambda:us-east-1:333344445555:function:pilot-patch-outcome-us-east-1-writer" } }
  mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:333344445555:log-group:/aws/lambda/pilot-patch-outcome-us-east-1-writer" } }
  mock_resource "aws_sqs_queue" { defaults = { arn = "arn:aws:sqs:us-east-1:333344445555:mock-queue" } }
  mock_resource "aws_cloudwatch_event_rule" { defaults = { arn = "arn:aws:events:us-east-1:333344445555:rule/mock-rule" } }
}
mock_provider "aws" {
  alias = "secondary"
  mock_data "aws_caller_identity" { defaults = { account_id = "333344445555" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "us-west-2", name = "us-west-2" } }
  mock_data "aws_iam_account_alias" { defaults = { account_alias = "pilot" } }
  mock_resource "aws_lambda_function" { defaults = { arn = "arn:aws:lambda:us-west-2:333344445555:function:pilot-patch-outcome-us-west-2-writer" } }
  mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-west-2:333344445555:log-group:/aws/lambda/pilot-patch-outcome-us-west-2-writer" } }
  mock_resource "aws_sqs_queue" { defaults = { arn = "arn:aws:sqs:us-west-2:333344445555:mock-queue" } }
  mock_resource "aws_cloudwatch_event_rule" { defaults = { arn = "arn:aws:events:us-west-2:333344445555:rule/mock-rule" } }
}
variables {
  member_account_id   = "333344445555"
  organization_id     = "o-example1234"
  archive_bucket_name = "central-patching-logs-111122223333"
}

run "second_member_two_regions_one_identity" {
  command = apply
  assert {
    condition     = output.regional_resources.primary.writer_role_created && !output.regional_resources.secondary.writer_role_created
    error_message = "Only the primary Lambda deployment must own the shared role."
  }
  assert {
    condition     = output.central_prerequisites.bucket_policy_statement.Condition.StringEquals["aws:PrincipalOrgID"] == var.organization_id
    error_message = "The primary deployment must export resolved statements for the existing central policies."
  }
  assert {
    condition     = output.regional_resources.primary.writer_role_arn == output.regional_resources.secondary.writer_role_arn
    error_message = "Both regions must use exactly one account identity."
  }
  assert {
    condition     = output.regional_resources.primary.package_bucket != output.regional_resources.secondary.package_bucket
    error_message = "Each region needs its own deployment bucket."
  }
  assert {
    condition     = output.regional_resources.primary.function_name == "pilot-patch-outcome-us-east-1-writer" && output.regional_resources.secondary.function_name == "pilot-patch-outcome-us-west-2-writer"
    error_message = "Shared Lambda names and archive paths must be regional."
  }
  assert {
    condition     = strcontains(output.canary_commands.primary, "us-east-1") && strcontains(output.canary_commands.secondary, "us-west-2")
    error_message = "Each canary targets its own region."
  }
}
