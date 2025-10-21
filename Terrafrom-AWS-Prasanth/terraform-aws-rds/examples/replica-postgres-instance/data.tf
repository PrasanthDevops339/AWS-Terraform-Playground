# Data Sources
data "aws_iam_account_alias" "current" {}

# Data source to pull vpc_id
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["erieins-dev-vpc-use2"]
  }
}

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
