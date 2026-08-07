terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.47.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }

  cloud {}
}

provider "aws" {
  region = "us-east-2"

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/prasanth-tfe-assume-role"
  }

  default_tags {
    tags = local.default_tags
  }
}
