# ============================================================================
# TERRAFORM VERSION REQUIREMENTS
# ============================================================================
# Defines the minimum Terraform version and required provider versions
# This ensures compatibility with the features used in this module

terraform {
  # Terraform CLI version requirement
  # >= 1.0 required for stable features like for_each, timecmp(), etc.
  required_version = ">= 1.0"

  # Provider version constraints
  required_providers {
    aws = {
      source  = "hashicorp/aws"  # Official AWS provider from HashiCorp registry
      version = ">= 5.0"         # AWS provider 5.0+ required for DECLARATIVE_POLICY_EC2 support
    }
  }
}

# ============================================================================
# AWS PROVIDER CONFIGURATION
# ============================================================================
# Configure the AWS provider with default region
# Credentials are read from AWS CLI config, environment variables, or IAM role

provider "aws" {
  region = var.aws_region  # Default region for API calls (from variables.tf)
}
