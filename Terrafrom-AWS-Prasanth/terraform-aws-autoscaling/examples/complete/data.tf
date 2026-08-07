data "aws_ami" "rhel8" {
  executable_users = ["self"]
  most_recent      = true
  owners           = [var.ami_owner_account_id]

  filter {
    name   = "name"
    values = ["prasanth-rhel8-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ami" "rhel8_use1" {
  executable_users = ["self"]
  most_recent      = true
  region           = "us-east-1"
  owners           = [var.ami_owner_account_id]

  filter {
    name   = "name"
    values = ["prasanth-rhel8-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["prasanth-dev-vpc-use2"]
  }
}

data "aws_vpc" "main_use1" {
  region = "us-east-1"

  filter {
    name   = "tag:Name"
    values = ["prasanth-dev-vpc-use1"]
  }
}
