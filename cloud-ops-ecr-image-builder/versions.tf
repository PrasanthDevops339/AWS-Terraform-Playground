terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key    = "servicenow_integration"
    region = "us-east-2"
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      "finops:application" = "1"
      "finops:portfolio"   = ""
      "finops:costcenter"  = ""
      Environment           = var.environment
      Owner                 = "cloudops_dl@examplecorp.com"
      Component             = "ServiceNow Integration"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      "finops:application" = ""
      "finops:portfolio"   = ""
      "finops:costcenter"  = ""
      Environment           = var.environment
      Owner                 = "cloudops_dl@examplecorp.com"
      Component             = "ServiceNow Integration"
    }
  }
}
