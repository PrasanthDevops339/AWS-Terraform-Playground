# Development Environment Configuration
# This is an example of how to use the modules in a specific environment

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  enable_nat_gateway   = false

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Example S3 bucket for development
module "dev_bucket" {
  source = "../../modules/s3"

  bucket_name       = "${var.project_name}-${var.environment}-${random_string.bucket_suffix.result}"
  enable_versioning = false
  enable_encryption = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Random string for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}