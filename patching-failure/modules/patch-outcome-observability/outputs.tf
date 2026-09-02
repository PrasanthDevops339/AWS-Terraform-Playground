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
  description = "Name of the per-account S3 bucket holding the Lambda deployment zip."
  value       = aws_s3_bucket.lambda_package.id
}

output "lambda_log_group_name" {
  description = "Name of the Lambda's CloudWatch log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "writer_role_arn" {
  description = "ARN of the Lambda execution role. Its name must match arn:<partition>:iam::*:role/<writer_role_name> in the central bucket and KMS key policies."
  value       = aws_iam_role.writer.arn
}

output "target_dlq_url" {
  description = "URL of the queue that catches EventBridge-could-not-invoke-Lambda failures."
  value       = module.target_dlq.queue_url
}

output "lambda_dlq_url" {
  description = "URL of the queue that catches Lambda-ran-and-threw failures (bucket policy, KMS grant, S3 errors)."
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
  description = "The two statements the CENTRAL bucket owner must merge into the bucket policy and KMS key policy. This module does not create or modify the bucket, its policy, or the KMS key -- see central-prerequisites/README.md for the same content with instructions."
  value = {
    bucket_policy_statement = {
      Sid       = "AllowPatchOutcomeWritersFromOrg"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:PutObject"
      Resource  = "arn:${local.partition}:s3:::${var.archive_bucket_name}/${var.archive_s3_prefix}/*"
      Condition = {
        StringEquals = { "aws:PrincipalOrgID" = "o-xxxxxxxxxx" }
        ArnLike      = { "aws:PrincipalArn" = "arn:${local.partition}:iam::*:role/${var.writer_role_name}" }
      }
    }
    kms_key_policy_statement = {
      Sid       = "AllowPatchOutcomeWritersFromOrg"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"]
      Resource  = "*"
      Condition = {
        StringEquals = { "aws:PrincipalOrgID" = "o-xxxxxxxxxx" }
        ArnLike      = { "aws:PrincipalArn" = "arn:${local.partition}:iam::*:role/${var.writer_role_name}" }
      }
    }
  }
}
