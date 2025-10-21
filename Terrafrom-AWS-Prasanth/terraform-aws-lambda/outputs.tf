# ===============================
# LAMBDA FUNCTION – Lambda outputs
# ===============================

output "lambda_arn" {
  description = "The ARN (Amazon Resource Name) of the lambda function"
  value       = element(concat(aws_lambda_function.main.*.arn, [""]), 0)
}

output "lambda_name" {
  description = "The name of the lambda function"
  value       = element(concat(aws_lambda_function.main.*.function_name, [""]), 0)
}

output "lambda_invoke_arn" {
  description = "The ARN to be used for invoking Lambda Function from API Gateway; to be used in aws_api_gateway_integration's uri"
  value       = element(concat(aws_lambda_function.main.*.invoke_arn, [""]), 0)
}

output "lambda_kms_key_arn" {
  description = "The ARN for the KMS encryption key of lambda function"
  value       = element(concat(aws_lambda_function.main.*.kms_key_arn, [""]), 0)
}

output "lambda_last_modified" {
  description = "The last modified date of this lambda function"
  value       = element(concat(aws_lambda_function.main.*.last_modified, [""]), 0)
}

output "lambda_qualified_arn" {
  description = "The ARN identifying your Lambda Function Version (if versioning is enabled via publish = true)"
  value       = element(concat(aws_lambda_function.main.*.qualified_arn, [""]), 0)
}

output "lambda_signing_job_arn" {
  description = "The ARN of the signing job"
  value       = element(concat(aws_lambda_function.main.*.signing_job_arn, [""]), 0)
}

output "lambda_signing_profile_version_arn" {
  description = "The ARN of the signing profile version"
  value       = element(concat(aws_lambda_function.main.*.signing_profile_version_arn, [""]), 0)
}

output "lambda_source_code_hash" {
  description = "The base64-encoded representation of raw SHA-256 sum of the zip file"
  value       = element(concat(aws_lambda_function.main.*.source_code_hash, [""]), 0)
}

output "lambda_source_code_size" {
  description = "The size in bytes of the function .zip file"
  value       = element(concat(aws_lambda_function.main.*.source_code_size, [""]), 0)
}

output "lambda_version" {
  description = "The latest published version of your Lambda Function"
  value       = element(concat(aws_lambda_function.main.*.version, [""]), 0)
}

output "lambda_s3_key" {
  description = "The lambda zip file, s3 uploaded key"
  value       = element(concat([local.lambda_s3_key], [""]), 0)
}
