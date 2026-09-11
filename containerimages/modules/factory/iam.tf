locals {
  role_services = { builder = "ec2", ingest = "lambda", control = "lambda", monitor = "lambda", publisher = "codebuild", states = "states" }
  kms_actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
  scan_statements = [
    { Effect = "Allow", Action = ["ecr:DescribeImages", "ecr:DescribeImageScanFindings"], Resource = local.repository_arns },
    { Effect = "Allow", Action = ["inspector2:ListFindings"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = [var.primary_region, var.secondary_region] } } },
    { Effect = "Allow", Action = ["imagebuilder:GetImage"], Resource = "arn:aws:imagebuilder:${var.primary_region}:${var.account_id}:image/${var.name}-al2023/*" }
  ]
  table_statements = [{ Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"], Resource = aws_dynamodb_table.releases.arn }]
  evidence_statements = [
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.evidence.arn}/releases/*" },
    { Effect = "Allow", Action = local.kms_actions, Resource = aws_kms_key.primary.arn }
  ]
  notify_statements = [{ Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.alerts.arn }]
  runtime_statements = {
    ingest  = concat(local.scan_statements, local.table_statements, [{ Effect = "Allow", Action = ["states:StartExecution"], Resource = local.state_arn }])
    control = concat(local.scan_statements, local.table_statements, local.evidence_statements, local.notify_statements)
    monitor = concat(local.scan_statements, local.table_statements, local.evidence_statements, local.notify_statements, [
      { Effect = "Allow", Action = ["dynamodb:Query"], Resource = "${aws_dynamodb_table.releases.arn}/index/kind" },
      { Effect = "Allow", Action = ["imagebuilder:StartImagePipelineExecution"], Resource = local.pipeline_arn }
    ])
    publisher = concat(local.scan_statements, local.table_statements, local.evidence_statements, [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"], Resource = ["${local.primary_base}${local.staging_name}", "${local.primary_base}${local.approved_name}", "${local.primary_base}${local.worker_repo}"] },
      { Effect = "Allow", Action = ["ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"], Resource = "${local.primary_base}${local.approved_name}" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = "${aws_s3_bucket.evidence.arn}/automation/*" }
    ])
  }
}
resource "aws_iam_role" "worker" {
  for_each = local.role_services
  name     = "${var.name}-${each.key}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "${each.value}.amazonaws.com" }
    Condition = contains(["publisher", "states"], each.key) ? {
      StringEquals = { "aws:SourceAccount" = var.account_id }
      ArnEquals    = { "aws:SourceArn" = each.key == "publisher" ? "arn:aws:codebuild:${var.primary_region}:${var.account_id}:project/${var.name}-promote" : local.state_arn }
    } : {}
  }] })
}
resource "aws_iam_role_policy" "runtime" {
  for_each = local.runtime_statements
  name     = "${var.name}-${each.key}"
  role     = aws_iam_role.worker[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = concat(each.value, [
    { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.workers[each.key].arn}:*" },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.primary.arn }
  ]) })
}
resource "aws_iam_role_policy" "no_scan_forgery" {
  for_each = toset(["control", "monitor", "publisher"])
  name     = "protect-scan-evidence"
  role     = aws_iam_role.worker[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Deny", Action = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:BatchWriteItem"],
    Resource  = aws_dynamodb_table.releases.arn,
    Condition = { "ForAnyValue:StringLike" = { "dynamodb:LeadingKeys" = ["SCAN#*"] } }
  }] })
}
resource "aws_iam_instance_profile" "builder" {
  name = "${var.name}-builder"
  role = aws_iam_role.worker["builder"].name
}
resource "aws_iam_role_policy_attachment" "builder_ssm" {
  role       = aws_iam_role.worker["builder"].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "builder_core" {
  role       = aws_iam_role.worker["builder"].name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}
resource "aws_iam_role_policy" "builder" {
  role = aws_iam_role.worker["builder"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"], Resource = "${local.primary_base}${local.staging_name}" },
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.evidence.arn}/build-logs/*" },
    { Effect = "Allow", Action = local.kms_actions, Resource = aws_kms_key.primary.arn }
  ] })
}
resource "aws_iam_role_policy" "states" {
  role = aws_iam_role.worker["states"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = aws_lambda_function.workers["control"].arn },
    { Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:StopBuild", "codebuild:BatchGetBuilds"], Resource = aws_codebuild_project.promotion.arn },
    { Effect = "Allow", Action = ["events:PutRule", "events:PutTargets", "events:DescribeRule"], Resource = "arn:aws:events:${var.primary_region}:${var.account_id}:rule/StepFunctionsGetEventForCodeBuildStartBuildRule" },
    { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets", "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"], Resource = "*" }
  ] })
}
