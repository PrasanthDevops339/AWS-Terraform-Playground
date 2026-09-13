terraform {
  # Below lines needed to run a plan with local code changes in TFE against target project/workspace
  # Plans will run in TFE without requiring commits to the remote repository
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x is required for data.aws_region.region and by the shared
      # terraform-aws-sqs module used by the (disabled) DLQ enhancement.
      version = ">= 6.0.0, < 7.0.0"
    }
    archive = {
      # Used transitively by the shared terraform-aws-lambda module to zip src/.
      source  = "hashicorp/archive"
      version = ">= 2.4.0, < 3.0.0"
    }
  }

  # Organization/workspace come from TF_CLOUD_ORGANIZATION / TF_WORKSPACE.
  # Set the workspace's Terraform working directory to "patching-failure" so
  # the sibling ../Terrafrom-AWS-Prasanth modules are uploaded with the run.
  cloud {}
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/prasa-tfe-assume-role" # sandbox. Change it as per your destination account
  }

  # Guard: fail if the assumed role resolves to a different account.
  allowed_account_ids = [var.account_id]

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
