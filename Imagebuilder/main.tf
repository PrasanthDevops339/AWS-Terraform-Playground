# ---------------------------------------------------------------------------
# DataSync EC2 agent AMI
# ---------------------------------------------------------------------------
resource "aws_cloudformation_stack" "datasync_ami_imagebuilder" {
  name          = var.stack_name
  template_body = file("${path.module}/AWS-DataSync-AMI.yaml")

  # DatasyncSsmPath is of type AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>.
  # Pass the SSM parameter path as a string — CloudFormation resolves it to the
  # current AMI ID at deploy/update time.
  parameters = {
    DatasyncSsmPath = var.datasync_ssm_path
    SubnetId        = var.subnet_id
    VPCId           = var.vpc_id
    KMSKeyUSE2      = var.kms_key_use2
    KMSKeyUSE1      = var.kms_key_use1
    AppName         = var.app_name
    ImageVersion    = var.image_version
    InstanceType    = var.instance_type
    KeyPair         = var.key_pair
    StackName       = var.stack_name
    OrganizationArn = var.organization_arn
    LoggingBucket   = var.logging_bucket
    CostCenter      = var.cost_center
    Environment     = var.environment
  }

  capabilities = ["CAPABILITY_NAMED_IAM"]

  tags = {
    ManagedBy   = "terraform"
    Environment = var.environment
    CostCenter  = var.cost_center
  }
}

# ---------------------------------------------------------------------------
# Storage Gateway FILE_S3 AMI
# Set enable_storage_gateway = true in your tfvars to deploy this stack.
# ---------------------------------------------------------------------------

# Upload the CloudFormation template to S3 before deploying the stack.
resource "aws_s3_object" "storagegateway_file_s3_template" {
  count = var.enable_storage_gateway ? 1 : 0

  bucket                 = var.logging_bucket
  key                    = "cft-template/PRASANTH-AWS-StorageGateway-FILE-S3-AMI.yaml"
  source                 = "${path.module}/AWS-StorageGateway-FILE-S3-AMI.yaml"
  etag                   = filemd5("${path.module}/AWS-StorageGateway-FILE-S3-AMI.yaml")
  server_side_encryption = "AES256"
}

resource "aws_cloudformation_stack" "storage_gateway_file_s3_imagebuilder" {
  count = var.enable_storage_gateway ? 1 : 0

  name               = var.sg_stack_name
  timeout_in_minutes = 90
  template_url       = "https://${var.logging_bucket}.s3.us-east-2.amazonaws.com/${aws_s3_object.storagegateway_file_s3_template[0].key}"
  on_failure         = "ROLLBACK"
  capabilities       = ["CAPABILITY_NAMED_IAM"]

  # No build-instance parameters (SubnetId, VPCId, InstanceType, KeyPair,
  # ImageVersion, StackName, LoggingBucket) — the new template uses Lambda +
  # ec2:CopyImage instead of Image Builder, so no build instance is launched.
  parameters = {
    StorageGatewaySsmPath    = var.storage_gateway_ssm_path
    KMSKeyUSE2               = var.kms_key_use2
    KMSKeyUSE1               = var.kms_key_use1
    AppName                  = var.sg_app_name
    OrganizationArn          = var.organization_arn
    DevDistributionAccountId = var.dev_distribution_account_id
    CostCenter               = var.cost_center
    Environment              = var.environment
  }

  timeouts {
    create = "90m"
    delete = "90m"
    update = "90m"
  }

  tags = {
    ManagedBy   = "terraform"
    Environment = var.environment
    CostCenter  = var.cost_center
    GatewayType = "FILE_S3"
    s3_etag     = aws_s3_object.storagegateway_file_s3_template[0].etag
  }

  depends_on = [aws_s3_object.storagegateway_file_s3_template]
}
