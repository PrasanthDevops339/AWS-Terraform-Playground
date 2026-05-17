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
resource "aws_cloudformation_stack" "storage_gateway_file_s3_imagebuilder" {
  count = var.enable_storage_gateway ? 1 : 0

  name          = var.sg_stack_name
  template_body = file("${path.module}/AWS-StorageGateway-FILE-S3-AMI.yaml")

  # StorageGatewaySsmPath is of type AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>.
  # Pass the SSM parameter path as a string — CloudFormation resolves it to the
  # current AMI ID at deploy/update time.
  parameters = {
    StorageGatewaySsmPath = var.storage_gateway_ssm_path
    SubnetId              = var.subnet_id
    VPCId                 = var.vpc_id
    KMSKeyUSE2            = var.kms_key_use2
    KMSKeyUSE1            = var.kms_key_use1
    AppName               = var.sg_app_name
    ImageVersion          = var.image_version
    InstanceType          = var.instance_type
    KeyPair               = var.key_pair
    StackName             = var.sg_stack_name
    OrganizationArn       = var.organization_arn
    LoggingBucket         = var.logging_bucket
    CostCenter            = var.cost_center
    Environment           = var.environment
  }

  capabilities = ["CAPABILITY_NAMED_IAM"]

  tags = {
    ManagedBy   = "terraform"
    Environment = var.environment
    CostCenter  = var.cost_center
    GatewayType = "FILE_S3"
  }
}
