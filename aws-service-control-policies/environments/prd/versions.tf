terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "acme-audit-prd-tf-backend-use2"
    use_lockfile = true
    key          = "aws-service-control-policies"
    region       = "us-east-2"
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      "finops:application"  = "platform_core_services"
      "finops:portfolio"    = "Technology Delivery"
      "finops:costcenter"   = ""
      "finops:owner"        = ""
      "admin:environment"   = "prd"
    }
  }
}
