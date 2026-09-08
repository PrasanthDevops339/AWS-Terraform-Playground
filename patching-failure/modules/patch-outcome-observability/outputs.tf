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
  description = "Core configuration this module hands the shared terraform-aws-lambda module (runtime, handler, sizing, package type, environment). Exposed so callers and tests can assert on the function contract without reaching into the shared module's internals."
  value       = local.writer_lambda_config
}

output "lambda_package_bucket" {
  description = "Name of the regional member-account S3 bucket holding the Lambda deployment zip."
  value       = aws_s3_bucket.lambda_package.id
}

output "lambda_log_group_name" {
  description = "Name of the Lambda's CloudWatch log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "writer_role_arn" {
  description = "ARN of the created or reused Lambda execution role, including its path. Waits for common permissions before additional regions use it."
  value       = local.writer_role_arn
  depends_on  = [aws_iam_role_policy.archive]
}

output "target_dlq_url" {
  description = "URL of the queue that catches EventBridge-could-not-invoke-Lambda failures."
  value       = module.target_dlq.queue_url
}

output "lambda_dlq_url" {
  description = "URL of the queue that catches Lambda asynchronous failure invocation records, including exhausted retries and expired events."
  value       = module.lambda_dlq.queue_url
}

output "archive_s3_destination" {
  description = "s3:// URI prefix this Lambda writes outcome records to."
  value       = "s3://${var.archive_bucket_name}/${var.archive_s3_prefix}"
}

output "canary_command" {
  description = "AWS CLI command to fire the canary event and prove end-to-end plumbing (Lambda, role, bucket policy, KMS grant) without impersonating a real SSM event."
  value = var.enable_canary ? (
    "aws events put-events --entries '[{\"Source\":\"custom.patch-canary\",\"DetailType\":\"canary\",\"Detail\":\"{}\"}]' --region ${local.region}"
  ) : null
}

output "central_prerequisites" {
  description = "Resolved statements for the central owners to merge. The KMS statement is null for SSE-S3. Null when reusing a role. No central resources are managed here."
  value = var.create_writer_role ? {
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
    kms_key_policy_statement = var.archive_kms_key_arn == null ? null : {
      Sid       = "AllowPatchOutcomeWritersFromOrg"
      Effect    = "Allow"
      Principal = "*"
      Action    = local.kms_actions
      Resource  = "*"
      Condition = local.central_condition
    }
  } : null
}

output "writer_role_created" {
  description = "Whether this deployment owns the shared Lambda execution role and common permissions."
  value       = var.create_writer_role
}
