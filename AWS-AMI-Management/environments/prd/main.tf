# ============================================================================
# AMI GOVERNANCE - PRODUCTION ENVIRONMENT
# ============================================================================
# Production environment configuration for AMI governance policies
# Uses the reusable ami-governance module with production-specific settings

# ============================================================================
# TERRAFORM & PROVIDER CONFIGURATION
# ============================================================================
terraform {
  # Terraform CLI version requirement
  required_version = ">= 1.0"

  # Provider version constraints
  required_providers {
    aws = {
      source  = "hashicorp/aws"  # Official AWS provider from HashiCorp registry
      version = ">= 5.0"         # AWS provider 5.0+ required for DECLARATIVE_POLICY_EC2 support
    }
    null = {
      source  = "hashicorp/null"  # For null_resource validation
      version = ">= 3.0"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region # Default region for API calls
}

# ============================================================================
# AMI GOVERNANCE MODULE INVOCATION
# ============================================================================
# Instantiate the ami-governance module with production configuration
# Module creates both declarative policy and SCP with specified allowlist

module "ami_governance" {
  source = "../../modules/ami-governance" # Path to reusable module

  # Environment configuration
  environment = var.environment # "prd" from auto.tfvars

  # Policy naming
  declarative_policy_name = "ami-governance-declarative-policy-prd"
  scp_policy_name         = "scp-ami-guardrail-prd"

  # Target IDs for policy attachment (Root/OUs/Accounts)
  target_ids = var.target_ids

  # AMI Publisher Allowlist
  ops_publisher_account    = var.ops_publisher_account    # Ops golden AMI account
  vendor_publisher_accounts = var.vendor_publisher_accounts # Approved vendors

  # Exception Management
  exception_accounts = var.exception_accounts # Time-bound exceptions with expiry dates

  # Enforcement Configuration
  enforcement_mode = var.enforcement_mode # audit_mode or enabled

  # Exception Request URL (shown in error messages)
  exception_request_url = var.exception_request_url

  # Resource Tags
  tags = var.tags
}
