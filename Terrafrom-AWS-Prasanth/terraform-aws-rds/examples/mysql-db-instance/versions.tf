terraform {
  # Local plans in TFE without committing
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.58.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/tfe-assume-role"
  }
}

variable "account_id" {
  type = string
}

locals {
  # just placeholder defaults mirroring screenshots
  tags = {
    "finops:application" = "platform_core_services"
    "finops:portfolio"   = "Technology Delivery"
    "finops:costcenter"  = "DT084"
    "finops:owner"       = "my_team_DL@example.com"
    "admin:environment"  = "dev"
  }
}
