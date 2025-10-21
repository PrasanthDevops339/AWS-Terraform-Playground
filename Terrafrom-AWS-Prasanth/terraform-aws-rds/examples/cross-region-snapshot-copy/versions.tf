################################################################################
# Terraform and Provider Configuration
################################################################################

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.92"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}

# Primary region provider (us-east-2)
provider "aws" {
  region = var.primary_region
  alias  = "primary"
}

# Secondary region provider (us-east-1) 
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}