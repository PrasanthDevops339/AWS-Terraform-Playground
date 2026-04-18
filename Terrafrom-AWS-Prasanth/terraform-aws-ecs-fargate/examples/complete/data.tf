########################################
# examples/complete/data.tf
########################################

data "aws_caller_identity" "current" {}

data "aws_iam_account_alias" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["${var.environment}-vpc"]
  }
}

# Private subnets — ECS tasks + internal ALB
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-private-*"]
  }
}

# Public subnets — internet-facing ALB
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-public-*"]
  }
}

# Data subnets — EFS mount targets
data "aws_subnets" "data" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-data-*"]
  }
}
