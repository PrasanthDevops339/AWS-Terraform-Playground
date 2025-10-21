################################################################################
# Data Sources 
################################################################################

# Common data sources (using primary provider)
data "aws_iam_account_alias" "current" {
  provider = aws.primary
}

# Primary region (us-east-2) - VPC by tag
data "aws_vpc" "primary" {
  provider = aws.primary
  
  filter {
    name   = "tag:Name"
    values = ["erieins-dev-vpc-use2"]
  }
}

# Subnets in primary VPC
data "aws_subnets" "primary" {
  provider = aws.primary
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
}

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

# Secondary region (us-east-1) - VPC by tag
data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = ["erieins-dev-vpc-use1"]  # Assuming similar naming pattern for us-east-1
  }
}

# Subnets in secondary VPC
data "aws_subnets" "secondary" {
  provider = aws.secondary
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

# DB Subnet Group for primary region
data "aws_db_subnet_group" "primary" {
  provider = aws.primary
  name     = "erieins-dev-db-subnet-group-use2"  # Update with your subnet group name
}

# IAM role for RDS enhanced monitoring
data "aws_iam_role" "rds_enhanced_monitoring" {
  provider = aws.primary
  name     = "rds-monitoring-role"
}