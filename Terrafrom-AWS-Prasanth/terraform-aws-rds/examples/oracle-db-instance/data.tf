# Data Sources
data "aws_iam_account_alias" "current" {}

# VPC by tag
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["erieins-dev-vpc-use2"]
  }
}

# Subnets in that VPC
data "aws_subnets" "data" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}
