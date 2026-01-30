terraform {
  # Below lines needed to run a plan with local code changes in TFE against target project/workspace
  # Plans will run in TFE without requiring commits to the remote repository

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=6.0.0"
    }
  }
}

cloud {}

provider "aws" {
  region = "us-east-2"

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/prasan-tfe-assume-role"
  }

  default_tags {
    tags = {
      # PLEASE DO NOT USE SHOWN COSTCENTER TAG VALUE
      "finops:application"  = "platform_core_services"
      "finops:portfolio"    = "Technology Delivery"
      "finops:costcenter"   = "ETD04"
      "finops:owner"        = "my_team_DL@example.com"
      "admin:environment"   = "dev"
      "example"             = "simple"
    }
  }
}
