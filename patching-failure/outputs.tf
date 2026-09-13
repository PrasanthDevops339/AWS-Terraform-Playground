output "event_rule_arns" {
  description = "ARNs of all EventBridge rules created (three SSM rules plus the canary, if enabled)."
  value = merge(
    { for k, r in aws_cloudwatch_event_rule.ssm : k => r.arn },
    var.enable_canary ? { canary = aws_cloudwatch_event_rule.canary[0].arn } : {}
  )
}

output "lambda_function_arn" {
  description = "ARN of the patch outcome writer Lambda."
  value       = module.writer_lambda.lambda_arn
}

output "lambda_function_name" {
  description = "Name of the patch outcome writer Lambda (account-alias prefixed by the shared module)."
  value       = module.writer_lambda.lambda_name
}

output "writer_lambda_config" {
  description = "Core configuration handed to the shared terraform-aws-lambda module, exposed so tests can assert on the function contract."
  value       = local.writer_lambda_config
}

output "lambda_package_bucket" {
  description = "Name of the S3 bucket holding the Lambda deployment zip."
  value       = aws_s3_bucket.lambda_package.id
}

output "lambda_log_group_name" {
  description = "Existing CloudWatch log group the Lambda writes to (streams are named after the function)."
  value       = data.aws_cloudwatch_log_group.app.name
}

output "writer_role_arn" {
  description = "ARN of the Lambda execution role, including its path."
  value       = local.writer_role_arn
  depends_on  = [aws_iam_role_policy.archive]
}

# ENHANCEMENT (DLQ): uncomment with the queues in main.tf.
# output "target_dlq_url" {
#   description = "URL of the queue that catches EventBridge-could-not-invoke-Lambda failures."
#   value       = module.target_dlq.queue_url
# }
#
# output "lambda_dlq_url" {
#   description = "URL of the queue that catches Lambda asynchronous failure invocation records."
#   value       = module.lambda_dlq.queue_url
# }

output "archive_s3_destination" {
  description = "s3:// URI prefix this Lambda writes outcome records to."
  value       = "s3://${var.archive_bucket_name}/${var.archive_s3_prefix}"
}

output "canary_command" {
  description = "AWS CLI command to fire the canary event and prove end-to-end plumbing without impersonating a real SSM event."
  value = var.enable_canary ? (
    "aws events put-events --entries '[{\"Source\":\"custom.patch-canary\",\"DetailType\":\"canary\",\"Detail\":\"{}\"}]' --region ${local.region}"
  ) : null
}

output "central_prerequisites" {
  description = "Resolved statements for the central bucket/KMS owners to merge. Both are required because the archive is SSE-KMS. No central resources are managed here."
  value = {
    bucket_policy_statement = {
      Sid       = "AllowPatchOutcomeWritersFromOrg"
      Effect    = "Allow"
      Principal = "*"
      Action    = local.s3_actions
      Resource  = local.archive_object_arn
      Condition = merge(local.central_condition, {
        StringEquals = merge(local.central_condition.StringEquals,
          var.archive_object_acl == null ? {} : { "s3:x-amz-acl" = var.archive_object_acl }
        )
      })
    }
    kms_key_policy_statement = {
      Sid       = "AllowPatchOutcomeWritersFromOrg"
      Effect    = "Allow"
      Principal = "*"
      Action    = local.kms_actions
      Resource  = "*"
      Condition = local.central_condition
    }
  }
}
