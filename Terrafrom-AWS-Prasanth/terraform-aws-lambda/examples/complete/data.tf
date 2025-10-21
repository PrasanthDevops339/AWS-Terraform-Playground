data "aws_iam_account_alias" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["ins-dev-vpc-use2"]
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-app-*"]
  }
}

data "aws_s3_bucket" "bootstrap" {
  bucket = "${data.aws_iam_account_alias.current.account_alias}-bootstrap-use2"
}
