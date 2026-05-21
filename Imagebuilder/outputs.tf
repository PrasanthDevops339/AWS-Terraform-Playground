output "ami_id" {
  description = "ID of the Operations-owned DataSync AMI produced by the initial Image Builder run."
  value       = aws_cloudformation_stack.datasync_ami_imagebuilder.outputs["AMIId"]
}

output "internal_ssm_param_name" {
  description = "Internal SSM parameter path holding the Operations-owned AMI ID."
  value       = aws_cloudformation_stack.datasync_ami_imagebuilder.outputs["InternalSsmParamName"]
}

output "pipeline_arn" {
  description = "ARN of the Image Builder pipeline for scheduled AMI refreshes."
  value       = aws_cloudformation_stack.datasync_ami_imagebuilder.outputs["PipelineArn"]
}

output "stack_id" {
  description = "CloudFormation stack ID."
  value       = aws_cloudformation_stack.datasync_ami_imagebuilder.id
}

# ---------------------------------------------------------------------------
# Storage Gateway FILE_S3 outputs (only populated when enable_storage_gateway = true)
# ---------------------------------------------------------------------------
output "sg_ami_id" {
  description = "ID of the Operations-owned Storage Gateway FILE_S3 AMI (us-east-2)."
  value       = var.enable_storage_gateway ? aws_cloudformation_stack.storage_gateway_file_s3_imagebuilder[0].outputs["AMIId"] : null
}

output "sg_ami_id_use1" {
  description = "ID of the Operations-owned Storage Gateway FILE_S3 AMI (us-east-1)."
  value       = var.enable_storage_gateway ? aws_cloudformation_stack.storage_gateway_file_s3_imagebuilder[0].outputs["AMIIdUSE1"] : null
}

output "sg_internal_ssm_param_name" {
  description = "Internal SSM parameter path holding the Storage Gateway AMI ID."
  value       = var.enable_storage_gateway ? aws_cloudformation_stack.storage_gateway_file_s3_imagebuilder[0].outputs["InternalSsmParamName"] : null
}

output "sg_lambda_arn" {
  description = "ARN of the Lambda function that copies and refreshes the Storage Gateway AMI."
  value       = var.enable_storage_gateway ? aws_cloudformation_stack.storage_gateway_file_s3_imagebuilder[0].outputs["LambdaFunctionArn"] : null
}

output "sg_refresh_rule_arn" {
  description = "ARN of the EventBridge rule driving the weekly Storage Gateway AMI refresh."
  value       = var.enable_storage_gateway ? aws_cloudformation_stack.storage_gateway_file_s3_imagebuilder[0].outputs["RefreshRuleArn"] : null
}

output "sg_stack_id" {
  description = "CloudFormation stack ID for the Storage Gateway stack."
  value       = var.enable_storage_gateway ? aws_cloudformation_stack.storage_gateway_file_s3_imagebuilder[0].id : null
}
