terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      "finops:application"  = "platform_core_services"
      "finops:portfolio"   = "Technology Delivery"
      "finops:costcenter"  = "DTD04"
      "finops:owner"       = "Angela Ratis-Buford"
      "admin:environment"  = "prd"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "use1"

  default_tags {
    tags = {
      "finops:application" = "platform_core_services"
      "finops:portfolio"  = "Technology Delivery"
      "finops:costcenter" = "DTD04"
      "finops:owner"      = "Angela Ratis-Buford"
      "admin:environment" = "dev"
    }
  }
}
