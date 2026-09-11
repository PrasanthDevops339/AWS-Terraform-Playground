resource "aws_cloudwatch_log_group" "workers" {
  for_each          = toset(["ingest", "control", "monitor", "publisher"])
  name              = each.key == "publisher" ? "/aws/codebuild/${var.name}-promote" : "/aws/lambda/${var.name}-${each.key}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.primary.arn
}
resource "aws_lambda_function" "workers" {
  #checkov:skip=CKV_AWS_117:These workers access public AWS APIs only; no private application-network access or NAT is needed.
  #checkov:skip=CKV_AWS_272:AWS Signer code-signing profiles require enterprise ownership and are deferred; deployment uses reviewed content-hashed artifacts and restricted roles.

  for_each                       = toset(["ingest", "control", "monitor"])
  function_name                  = "${var.name}-${each.key}"
  description                    = "AL2023 trusted release ${each.key} worker"
  role                           = aws_iam_role.worker[each.key].arn
  runtime                        = "python3.12"
  architectures                  = ["x86_64"]
  handler                        = "factory.${each.key}"
  filename                       = data.archive_file.lambda.output_path
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  timeout                        = each.key == "monitor" ? 300 : 120
  memory_size                    = 256
  reserved_concurrent_executions = each.key == "monitor" ? 1 : 5
  kms_key_arn                    = aws_kms_key.primary.arn
  environment {
    variables = merge(local.runtime_env, {
      SCAN_TIMEOUT_SECONDS        = tostring(var.scan_timeout_seconds)
      REPLICATION_TIMEOUT_SECONDS = tostring(var.replication_timeout_seconds)
    })
  }
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
  depends_on = [aws_cloudwatch_log_group.workers, aws_iam_role_policy.runtime, aws_iam_role_policy.lambda_dlq]
}
resource "aws_lambda_function_event_invoke_config" "workers" {
  for_each                     = aws_lambda_function.workers
  function_name                = each.value.function_name
  maximum_event_age_in_seconds = 3600
  maximum_retry_attempts       = 2
}
resource "aws_codebuild_project" "promotion" {
  name                   = "${var.name}-promote"
  description            = "Trusted digest-preserving release publisher; no candidate code execution"
  service_role           = aws_iam_role.worker["publisher"].arn
  encryption_key         = aws_kms_key.primary.arn
  build_timeout          = 30
  queued_timeout         = 30
  concurrent_build_limit = 1
  artifacts {
    type = "NO_ARTIFACTS"
  }
  source {
    type     = "S3"
    location = "${aws_s3_bucket.evidence.id}/${aws_s3_object.promotion.key}"
    buildspec = yamlencode({ version = "0.2", "run-as" = "factory", phases = {
      build = { commands = ["set -eu", "test -n \"$CANDIDATE_DIGEST\"", "python3 promote.py"] }
    } })
  }
  environment {
    type                        = "LINUX_CONTAINER"
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.promotion_worker_image
    image_pull_credentials_type = "SERVICE_ROLE"
    privileged_mode             = false
    dynamic "environment_variable" {
      for_each = local.runtime_env
      content {
        name  = environment_variable.key
        value = environment_variable.value
        type  = "PLAINTEXT"
      }
    }
  }
  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.workers["publisher"].name
    }
  }
  lifecycle {
    precondition {
      condition     = startswith(var.promotion_worker_image, "${var.account_id}.dkr.ecr.${var.primary_region}.amazonaws.com/")
      error_message = "The trusted worker must be in this account and primary Region."
    }
  }
}
locals {
  lambda_retry   = [{ ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"], IntervalSeconds = 2, MaxAttempts = 5, BackoffRate = 2, JitterStrategy = "FULL" }]
  workflow_catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "RecordFailure" }]
}
resource "aws_cloudwatch_log_group" "states" {
  name              = "/aws/vendedlogs/states/${var.name}-release"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.primary.arn
}
resource "aws_sfn_state_machine" "release" {
  tracing_configuration { enabled = true }
  name     = "${var.name}-release"
  role_arn = aws_iam_role.worker["states"].arn
  type     = "STANDARD"
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.states.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
  definition = jsonencode({
    Comment        = "Fail-closed AL2023 scan, promotion and regional verification"
    StartAt        = "Evaluate"
    TimeoutSeconds = var.scan_timeout_seconds + var.replication_timeout_seconds + 7200
    States = {
      Evaluate = { Type = "Task", Resource = aws_lambda_function.workers["control"].arn,
        Parameters = { action = "evaluate", "digest.$" = "$.digest", "started_at.$" = "$.started_at" },
      ResultPath = "$.gate", Retry = local.lambda_retry, Catch = local.workflow_catch, Next = "GateResult" }
      GateResult = { Type = "Choice", Choices = [
        { Variable = "$.gate.status", StringEquals = "ACCEPTED", Next = "Promote" },
        { Variable = "$.gate.status", StringEquals = "PENDING", Next = "WaitForScan" }
      ], Default = "Rejected" }
      WaitForScan = { Type = "Wait", Seconds = 30, Next = "Evaluate" }
      Promote = { Type = "Task", Resource = "arn:aws:states:::codebuild:startBuild.sync",
        Parameters = { ProjectName = aws_codebuild_project.promotion.name,
        EnvironmentVariablesOverride = [{ Name = "CANDIDATE_DIGEST", "Value.$" = "$.digest", Type = "PLAINTEXT" }] },
      ResultPath = "$.promotion", Catch = local.workflow_catch, Next = "ReplicationStart" }
      ReplicationStart = { Type = "Pass", Parameters = { "started_at.$" = "$$.State.EnteredTime" }, ResultPath = "$.replication", Next = "VerifyReplication" }
      VerifyReplication = { Type = "Task", Resource = aws_lambda_function.workers["control"].arn,
        Parameters = { action = "replication", "digest.$" = "$.digest", "started_at.$" = "$.replication.started_at" },
      ResultPath = "$.gate", Retry = local.lambda_retry, Catch = local.workflow_catch, Next = "ReplicationResult" }
      ReplicationResult = { Type = "Choice", Choices = [
        { Variable = "$.gate.status", StringEquals = "RELEASED", Next = "Released" },
        { Variable = "$.gate.status", StringEquals = "PENDING", Next = "WaitForReplication" }
      ], Default = "Rejected" }
      WaitForReplication = { Type = "Wait", Seconds = 60, Next = "VerifyReplication" }
      Rejected           = { Type = "Pass", Parameters = { Error = "GateRejected", "Cause.$" = "$.gate.reason" }, ResultPath = "$.error", Next = "RecordFailure" }
      RecordFailure = { Type = "Task", Resource = aws_lambda_function.workers["control"].arn,
        Parameters = { action = "fail", "digest.$" = "$.digest", "reason.$" = "$.error" },
      ResultPath = "$.failure", Retry = local.lambda_retry, Next = "Failed" }
      Released = { Type = "Succeed" }
      Failed   = { Type = "Fail", Error = "ReleaseBlocked", Cause = "See release ledger and encrypted evidence" }
    }
  })
  depends_on = [aws_iam_role_policy.states]
}
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-events-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.primary.arn
}
resource "aws_iam_role_policy" "lambda_dlq" {
  for_each = toset(["ingest", "control", "monitor"])
  role     = aws_iam_role.worker[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.dlq.arn
  }] })
}
resource "aws_cloudwatch_event_rule" "build" {
  name = "${var.name}-build-events"
  event_pattern = jsonencode({ source = ["aws.imagebuilder"], "detail-type" = ["EC2 Image Builder Image State Change"],
    account = [var.account_id], detail = { state = { status = ["AVAILABLE"] } },
  resources = [{ prefix = "arn:aws:imagebuilder:${var.primary_region}:${var.account_id}:image/${var.name}-al2023/" }] })
}
resource "aws_cloudwatch_event_rule" "scans" {
  name = "${var.name}-scan-events"
  event_pattern = jsonencode({ source = ["aws.inspector2"], "detail-type" = ["Inspector2 Scan"],
  account = [var.account_id], detail = { "scan-status" = ["INITIAL_SCAN_COMPLETE"] } })
}
resource "aws_cloudwatch_event_target" "ingest" {
  for_each  = { build = aws_cloudwatch_event_rule.build.name, scans = aws_cloudwatch_event_rule.scans.name }
  rule      = each.value
  target_id = "ingest"
  arn       = aws_lambda_function.workers["ingest"].arn
  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }
}
resource "aws_lambda_permission" "ingest" {
  for_each       = { build = aws_cloudwatch_event_rule.build.arn, scans = aws_cloudwatch_event_rule.scans.arn }
  statement_id   = "EventBridge${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.workers["ingest"].function_name
  principal      = "events.amazonaws.com"
  source_arn     = each.value
  source_account = var.account_id
}
resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sqs:SendMessage", Resource = aws_sqs_queue.dlq.arn,
    Condition = { ArnLike = { "aws:SourceArn" = "arn:aws:events:${var.primary_region}:${var.account_id}:rule/${var.name}-*" } }
  }] })
}
