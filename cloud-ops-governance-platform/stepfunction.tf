#######################STEP FUNCTION COMPLIANCE DB INGESTION#######################
## Step Function to trigger Lambda Compliance DB Ingestion
##################################################################################
resource "aws_sfn_state_machine" "ccop-upload-state-machine" {
  name     = "${var.account_profile}-ccop-ingest-execution-engine"
  role_arn = aws_iam_role.ccop_upload_state_machine_role.arn
  definition = <<EOF
{
  "Comment": "Invoke Lambda compliance ingest functions and send failure notifications to SNS",
  "StartAt": "CCOPComplianceIngestLambda",
  "States": {
    "CCOPComplianceIngestLambda": {
      "Type": "Task",
      "Resource": "${module.lambda_compliance_ingest.lambda_arn}",
      "Next": "CheckIngestStatus",
      "Catch": [{
        "ErrorEquals": ["States.TaskFailed", "Lambda.Unknown"],
        "Next": "SendFailureNotification"
      }]
    },
    "CheckIngestStatus": {
      "Type": "Choice",
      "Choices": [{
        "Variable": "$.statusCode",
        "NumericEquals": 500,
        "Next": "SendFailureNotification"
      }],
      "Default": "CCOPComplianceRulesExecutionLambda"
    },
    "CCOPComplianceRulesExecutionLambda": {
      "Type": "Task",
      "Resource": "${module.lambda_compliance_execution.lambda_arn}",
      "Next": "CheckRulesStatus",
      "Catch": [{
        "ErrorEquals": ["States.TaskFailed", "Lambda.Unknown"],
        "Next": "SendFailureNotification"
      }]
    },
    "CheckRulesStatus": {
      "Type": "Choice",
      "Choices": [{
        "Variable": "$.statusCode",
        "NumericEquals": 500,
        "Next": "SendFailureNotification"
      }],
      "Default": "CCOPCompliancePolicyExecutionLambda"
    },
    "CCOPCompliancePolicyExecutionLambda": {
      "Type": "Task",
      "Resource": "${module.lambda_servicenow_eventmanager.lambda_arn}",
      "Next": "ChoiceState",
      "Catch": [{
        "ErrorEquals": ["States.TaskFailed", "Lambda.Unknown"],
        "Next": "SendFailureNotification"
      }]
    },
    "ChoiceState": {
      "Type": "Choice",
      "Choices": [{
        "Variable": "$.statusCode",
        "NumericEquals": 500,
        "Next": "SendFailureNotification"
      }],
      "Default": "SuccessState"
    },
    "SuccessState": {
      "Type": "Pass",
      "End": true
    },
    "SendFailureNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:sns:publish",
      "Parameters": {
        "TopicArn": "${module.step_function_failure_topic.sns_arn}",
        "Message.$": "States.Format('Step Function execution failed for CCOP Ingestion State Machine. Execution Arn: {}. Message: {}', $$.Execution.Id, $.Cause)"
      },
      "Next": "FailState"
    },
    "FailState": {
      "Type": "Fail",
      "Cause": "Lambda or Step Function internal error occurred.",
      "Error": "InternalServerError"
    }
  }
}
EOF
}