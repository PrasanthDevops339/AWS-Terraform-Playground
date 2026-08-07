data "aws_iam_account_alias" "current" {}

data "aws_vpc" "main" {
  region = var.region

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_subnets" "main" {
  region = var.region

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-${var.subnet_type}-*"]
  }
}
