################################################################################
# Terraform & Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.34.0" # Keep the POC on the same 6.x floor as the maintained upstream module
    }
  }
}
