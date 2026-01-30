# get the current working account details
data "aws_caller_identity" "current" {}

data "aws_iam_account_alias" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["test-placeholder-dev-vpc-use2"]
  }
}

data "aws_subnets" "app_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-app-*"]
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
