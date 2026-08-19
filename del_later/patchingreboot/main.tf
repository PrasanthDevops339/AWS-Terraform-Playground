##############################################################################
# Patch reboot telemetry
#
# Reacts to the centralized patching solution rather than wrapping it: when
# AWS-RunPatchBaseline* reaches a terminal status on an instance, EventBridge
# starts an Automation runbook that dispatches a Command document to the
# instance. The document decides reboot vs no-reboot and publishes
# PatchRunStatus and RebootOccurred to CloudWatch for Splunk Observability.
#
# Deploy per workload account via aft-global-customizations.
##############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  automation_definition_arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.trigger.name}:$DEFAULT"
}

data "aws_partition" "current" {}

##############################################################################
# SSM documents
##############################################################################

# Command document: runs ON the instance. Detects the reboot and publishes
# both metrics. Ships the full per-OS detection menu so a method can be
# swapped at implementation time.
resource "aws_ssm_document" "detect" {
  name            = var.detect_document_name
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/documents/detect-patch-reboot.yaml")
  tags            = var.tags
}

# Automation runbook: EventBridge target. Resolves Operation, Name and wave
# tags, and the start epoch, then dispatches the Command document.
#
# NOTE: the runbook references the Command document by the literal name
# "Detect-PatchReboot". Keep var.detect_document_name aligned with it, or
# parameterize DocumentName inside the runbook.
resource "aws_ssm_document" "trigger" {
  name            = var.trigger_document_name
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/documents/trigger-detect-patch-reboot.yaml")
  tags            = var.tags
}

##############################################################################
# IAM: Automation execution role
##############################################################################

data "aws_iam_policy_document" "automation_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    # Confused-deputy guard: only this account's SSM can assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "automation" {
  name               = var.automation_role_name
  assume_role_policy = data.aws_iam_policy_document.automation_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "automation" {
  # Resolve Install vs Scan so Scan runs never trigger detection.
  # ListCommands does not support resource-level permissions.
  statement {
    sid       = "ResolvePatchOperation"
    effect    = "Allow"
    actions   = ["ssm:ListCommands"]
    resources = ["*"]
  }

  # Resolve Name and patch:wave tags for metric dimensions.
  statement {
    sid       = "ResolveInstanceTags"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # Dispatch the detection document to the instance.
  statement {
    sid     = "DispatchDetectionDocument"
    effect  = "Allow"
    actions = ["ssm:SendCommand"]
    resources = [
      aws_ssm_document.detect.arn,
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
    ]
  }

  statement {
    sid       = "TrackDispatchedCommand"
    effect    = "Allow"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }

  # Fallback path: publish status + detection-gap metrics centrally when the
  # instance is unreachable or its own publish failed.
  statement {
    sid       = "PublishFallbackMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metric_namespace]
    }
  }
}

resource "aws_iam_role_policy" "automation" {
  name   = "${var.automation_role_name}-policy"
  role   = aws_iam_role.automation.id
  policy = data.aws_iam_policy_document.automation.json
}

##############################################################################
# IAM: EventBridge invocation role
##############################################################################

data "aws_iam_policy_document" "events_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "events" {
  name               = var.events_role_name
  assume_role_policy = data.aws_iam_policy_document.events_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "events" {
  statement {
    sid       = "StartDetectionAutomation"
    effect    = "Allow"
    actions   = ["ssm:StartAutomationExecution"]
    resources = [local.automation_definition_arn]
  }

  # Required so EventBridge can hand the execution role to Automation.
  statement {
    sid       = "PassAutomationRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.automation.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "events" {
  name   = "${var.events_role_name}-policy"
  role   = aws_iam_role.events.id
  policy = data.aws_iam_policy_document.events.json
}

##############################################################################
# EventBridge rule + target
##############################################################################

resource "aws_cloudwatch_event_rule" "patch_command_complete" {
  name        = var.rule_name
  description = "Fires detection when a patch command reaches a terminal status"

  event_pattern = jsonencode({
    source        = ["aws.ssm"]
    "detail-type" = ["EC2 Command Invocation Status-change Notification"]
    detail = {
      # Quick Setup patch policies commonly invoke the Association variant,
      # so all three patch documents are matched.
      "document-name" = var.patch_document_names
      status          = ["Success", "Failed", "TimedOut", "Cancelled"]
    }
  })

  tags = var.tags
}

# Automation is used as the target (not Run Command) because an EventBridge
# RunCommandTarget accepts only literal InstanceIds or tag values -- input
# transformer variables do not resolve inside them, so a Run Command target
# cannot aim at the instance named in the event. Automation targets do
# support the input transformer.
resource "aws_cloudwatch_event_target" "start_automation" {
  rule     = aws_cloudwatch_event_rule.patch_command_complete.name
  target_id = "start-detection-automation"
  arn      = local.automation_definition_arn
  role_arn = aws_iam_role.events.arn

  input_transformer {
    input_paths = {
      instanceId    = "$.detail.instance-id"
      commandId     = "$.detail.command-id"
      patchStatus   = "$.detail.status"
      requestedTime = "$.detail.requested-date-time"
    }

    # Automation parameters must be arrays of strings. The role ARN and
    # namespace are static; the rest come from the event.
    input_template = <<-EOT
      {
        "InstanceId": [<instanceId>],
        "CommandId": [<commandId>],
        "PatchStatus": [<patchStatus>],
        "RequestedTime": [<requestedTime>],
        "AutomationAssumeRole": ["${aws_iam_role.automation.arn}"],
        "MetricNamespace": ["${var.metric_namespace}"]
      }
    EOT
  }
}

##############################################################################
# Instance profile permission (optional)
#
# The detection document publishes metrics from the instance itself, so
# instance profiles need PutMetricData scoped to this namespace. Attach this
# policy to the existing patchable-instance role, or set
# create_instance_metric_policy = false and fold the statement into the AFT
# base instance profile policy instead.
##############################################################################

data "aws_iam_policy_document" "instance_metrics" {
  count = var.create_instance_metric_policy ? 1 : 0

  statement {
    sid       = "PublishPatchExecutionMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metric_namespace]
    }
  }
}

resource "aws_iam_policy" "instance_metrics" {
  count       = var.create_instance_metric_policy ? 1 : 0
  name        = var.instance_metric_policy_name
  description = "Allows patched instances to publish only ${var.metric_namespace} metrics"
  policy      = data.aws_iam_policy_document.instance_metrics[0].json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "instance_metrics" {
  for_each   = var.create_instance_metric_policy ? toset(var.instance_role_names) : toset([])
  role       = each.value
  policy_arn = aws_iam_policy.instance_metrics[0].arn
}
