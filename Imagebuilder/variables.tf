variable "datasync_ssm_path" {
  description = "AWS-owned SSM public parameter path for the DataSync EC2 agent AMI."
  type        = string
  default     = "/aws/service/datasync/ami"
}

variable "subnet_id" {
  description = "Subnet ID for the Image Builder build instance."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID that contains the build subnet."
  type        = string
}

variable "kms_key_use2" {
  description = "KMS key ARN or alias for us-east-2 AMI encryption."
  type        = string
}

variable "kms_key_use1" {
  description = "KMS key ARN or alias for us-east-1 AMI encryption."
  type        = string
}

variable "app_name" {
  description = "Application name prefix used for resource naming."
  type        = string
  default     = "PRASAN-AWS-DATASYNC-CF"
}

variable "image_version" {
  description = "Semantic version for the Image Builder recipe."
  type        = string
  default     = "1.0.0"
}

variable "instance_type" {
  description = "EC2 instance type for the Image Builder build instance."
  type        = string
  default     = "t3.medium"
}

variable "key_pair" {
  description = "EC2 Key Pair name for the Image Builder build instance."
  type        = string
}

variable "stack_name" {
  description = "CloudFormation stack name."
  type        = string
  default     = "PRASAN-AWS-DATASYNC-CF-Stack"
}

variable "organization_arn" {
  description = "ARN of the AWS Organization to share the AMI with."
  type        = string
}

variable "logging_bucket" {
  description = "S3 bucket name for Image Builder build logs."
  type        = string
}

variable "cost_center" {
  description = "CostCenter tag value."
  type        = string
  default     = "Test-Stacks"
}

variable "enable_storage_gateway" {
  description = "Set to true to deploy the Storage Gateway FILE_S3 Image Builder stack."
  type        = bool
  default     = false
}

variable "storage_gateway_ssm_path" {
  description = "AWS-owned SSM public parameter path for the Storage Gateway FILE_S3 AMI."
  type        = string
  default     = "/aws/service/storagegateway/ami/FILE_S3/latest"
}

variable "sg_app_name" {
  description = "Application name prefix used for Storage Gateway resource naming."
  type        = string
  default     = "PRASAN-AWS-STORAGEGATEWAY-FILE-S3-CF"
}

variable "sg_stack_name" {
  description = "CloudFormation stack name for the Storage Gateway stack."
  type        = string
  default     = "PRASAN-AWS-STORAGEGATEWAY-FILE-S3-CF-Stack"
}

variable "dev_distribution_account_id" {
  description = "AWS account ID that receives AMI launch permission in dev. Only this single account is targeted — not the whole org — to limit blast radius in non-prod."
  type        = string
  default     = "333333333333"
}

variable "environment" {
  description = "Deployment environment. Use 'prd' to enable distribution config and weekly Monday schedule."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prd"], var.environment)
    error_message = "environment must be 'dev' or 'prd'."
  }
}
