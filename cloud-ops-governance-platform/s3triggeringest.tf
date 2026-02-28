############################################################
# STEP 4 to 5 - Event rule triggers step function
# when (PutObject) data is uploaded to ccop-ingest
# S3 Bucket ingest location
############################################################

resource "aws_cloudwatch_event_rule" "bucket_upload_rule" {
  name        = "${var.account_profile}-bucket-upload-rule"
  description = "This rule is triggered when a file is uploaded to the appropriate S3 bucket location."

  event_pattern = <<PATTERN
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {
      "name": ["${module.ccop_ingest_reporting_bucket.bucket_name}"]
    },
    "object": {
      "key": [
        { "prefix": "ingest/aws-config/" }
      ]
    }
  }
}
PATTERN
}

############################################################
### STEP 4 to 5 - S3 Bucket Upload Trigger Rule
### to Define rule for S3 Trigger when data reaches
### S3 Bucket ingest location
############################################################

resource "aws_cloudwatch_event_target" "bucket_upload_trigger" {
  arn      = resource.aws_sfn_state_machine.ccop_upload_state_machine.arn
  rule     = aws_cloudwatch_event_rule.bucket_upload_rule.name
  role_arn  = aws_iam_role.amazon_eventbridge_invoke_step_function.arn
}

resource "aws_iam_role" "ccop_upload_state_machine_role" {
  name = "${var.account_profile}-ccop-upload-state-machine-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "states.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ccop_upload_state_machine_role_policy" {
  name = "${var.account_profile}-ccop-upload-state-machine-role-policy"
  role = aws_iam_role.ccop_upload_state_machine_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeTags",
          "sns:*",
          "lambda:InvokeFunction"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "amazon_eventbridge_invoke_step_function" {
  name = "${var.account_profile}-amazon-eventbridge-invoke-step-function"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "events.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "amazon_eventbridge_invoke_step_function_policy" {
  name = "${var.account_profile}-amazon-eventbridge-invoke-step-function-policy"
  role = aws_iam_role.amazon_eventbridge_invoke_step_function.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "states:StartExecution"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}