terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.81.0, < 6.0.0"
    }
  }

  backend "s3" {
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      "finops:application"   = "platform_core_services"
      "finops:portfolio"     = "Technology Delivery"
      "finops:costcenter"    = "DTD04"
      "finops:owner"         = "B"
      "admin:environment"    = "dev"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "use1"

  default_tags {
    tags = {
      "finops:application"   = "platform_core_services"
      "finops:portfolio"     = "Technology Delivery"
      "finops:costcenter"    = "DTD04"
      "finops:owner"         = "A"
      "admin:environment"    = "dev"
    }
  }
}
