terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.67.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/ins-tfe-assume-role"
  }

  default_tags {
    tags = {
      "finops:application" = "test-application"
      "finops:portfolio"   = "technology_delivery"
      "finops:costcenter"  = "XXXXX"
      "finops:owner"       = "my_team_DL@example.com"
      "admin:environment"  = "dev"
    }
  }
}


provider "aws" {
  alias  = "secondary"
  region = "us-east-1"
}
