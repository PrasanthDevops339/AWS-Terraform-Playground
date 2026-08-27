terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Example wiring for an AFT account-customizations repo. This file is the
# only place in this repo allowed to hardcode account-specific values --
# real ARNs, bucket names, org IDs, and regions.
module "patch_outcome_observability" {
  source = "../../modules/patch-outcome-observability"

  archive_bucket_name = "central-patching-logs-111122223333"
  archive_kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"

  # Deploy dormant; arm later by flipping this to true once the central
  # bucket policy and KMS key policy (see central_prerequisites output)
  # have been merged by the bucket owner.
  rules_enabled = false
  enable_canary = true

  tags = {
    Team        = "platform-engineering"
    ManagedBy   = "terraform"
    Application = "patch-outcome-observability"
  }
}

output "central_prerequisites" {
  value = module.patch_outcome_observability.central_prerequisites
}

output "canary_command" {
  value = module.patch_outcome_observability.canary_command
}
