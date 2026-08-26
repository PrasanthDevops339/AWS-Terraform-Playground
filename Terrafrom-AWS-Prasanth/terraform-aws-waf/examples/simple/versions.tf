terraform {
  # Below lines needed to run a plan with local code changes in TFE against target project/workspace
  # Plans will run in TFE without requiring commits to the remote repository

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }

  cloud {
    hostname     = "tfe.Prasanth.com"
    organization = "Prasanth"
  }
}

provider "aws" {
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/Prasanth-tfe-assume-role" # Sandbox. Change it as per your destination account
  }

  default_tags {
    tags = {
      "finops:application" = "test-application"
      "finops:portfolio"   = "technology_delivery"
      "finops:costcenter"  = "XXXX"
      "admin:environment"  = "dev"
      "finops:owner"       = "cloud_ops_dl@Prasanth.com"
    }
  }
}
