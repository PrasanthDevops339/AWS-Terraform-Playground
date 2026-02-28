terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
    mysql = {
      source  = "zph/mysql"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      "finops:application"  = "1"
      "finops:portfolio"    = "platform_core_services"
      "finops:costcenter"   = "Technology Delivery"
      Environment           = var.environment
      Owner                 = "cloudops_dl@prasanth.com"
      Component             = "CloudOps Compliance Automation Platform"
    }
  }
}

## Backend Configuration ##
terraform {
  backend "s3" {
    key    = "tf-backend-use2"
    region = "us-east-2"
  }
}