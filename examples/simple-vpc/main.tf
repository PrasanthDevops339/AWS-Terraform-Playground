# Create a simple VPC using our module
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  enable_nat_gateway   = false # Set to true if you need NAT gateways (costs money)

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Example     = "simple-vpc"
  }
}