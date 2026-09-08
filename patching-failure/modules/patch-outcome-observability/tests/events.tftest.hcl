# Fixtures model documented SSM event envelopes plus supported terminal aliases.
# This checks the exact generated JSON patterns offline. The runbook also calls
# AWS TestEventPattern in the pilot; synthetic canaries do not exercise SSM rules.
mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "222233334444" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "us-east-1" } }
  mock_data "aws_iam_account_alias" { defaults = { account_alias = "pilot" } }
}
variables {
  create_writer_role  = false
  archive_bucket_name = "central-patching-logs-111122223333"
  writer_role_arn     = "arn:aws:iam::222233334444:role/patch-outcome-s3-writer"
}
run "documented_event_envelopes_and_terminal_statuses" {
  command = plan
  assert {
    condition = alltrue([
      for fixture in jsondecode(file("${path.module}/../../tests/fixtures/event-patterns.json")) :
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
