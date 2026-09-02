terraform {
  # Below lines needed to run a plan with local code changes in TFE against target project/workspace
  # Plans will run in TFE without requiring commits to the remote repository

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }

  cloud {}
}

provider "aws" {
  region = "us-east-2"

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/prasa-tfe-assume-role" # sandbox. Change it as per your destination account
  }

  default_tags {
    tags = {
      "#finops:application" = "test-application"
      "#finops:portfolio"   = "technology_delivery"
      "#finops:costcenter"  = "xxxx"
      "admin:environment"   = "dev"
      "#finops:owner"       = "cloud_ops_dl@prasa.com"
    }
  }
}
