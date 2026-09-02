terraform {
  # Below lines needed to run a plan with local code changes in TFE against target project/workspace
  # Plans will run in TFE without requiring commits to the remote repository

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The resource-level `region` argument this example exercises is AWS
      # provider 6.x only.
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

###############################################################################
# Primary provider - us-east-2
#
# The whole point of this example is that the provider Region and the Region
# the Cognito resources land in are DIFFERENT. Leave this as us-east-2; the
# module's `region` input in main.tf is what moves the pool to us-east-1.
###############################################################################

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

# There is deliberately no second, aliased provider here. Both the cognito
# module and terraform-aws-waf take their own `region` input, so this whole
# example runs off the single us-east-2 provider above - which is the point of
# AWS provider 6.x enhanced region support.
