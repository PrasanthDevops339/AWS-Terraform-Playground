data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["ins-dev-vpc-use2"]
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
