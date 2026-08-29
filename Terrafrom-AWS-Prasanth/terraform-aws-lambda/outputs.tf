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

output "lambda_function_name" {
  description = "The name of the lambda function (alias of lambda_name, for consumers expecting *_function_name)"
  value       = element(concat(aws_lambda_function.main.*.function_name, [""]), 0)
}

output "lambda_config" {
  description = "Curated view of the deployed function's core configuration, so consumers can assert on what they asked for without reaching into module internals."
  value = length(aws_lambda_function.main) > 0 ? {
    runtime                        = aws_lambda_function.main[0].runtime
    handler                        = aws_lambda_function.main[0].handler
    memory_size                    = aws_lambda_function.main[0].memory_size
    timeout                        = aws_lambda_function.main[0].timeout
    package_type                   = aws_lambda_function.main[0].package_type
    architectures                  = aws_lambda_function.main[0].architectures
    reserved_concurrent_executions = aws_lambda_function.main[0].reserved_concurrent_executions
    environment                    = try(aws_lambda_function.main[0].environment[0].variables, {})
  } : null
}

