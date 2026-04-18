################################################################################
# Terraform & Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.4.0" # Required for ECS-native B/G, Linear, Canary strategies
    }
  }
}
