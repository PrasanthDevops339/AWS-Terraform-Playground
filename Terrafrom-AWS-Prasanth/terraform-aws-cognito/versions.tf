terraform {
  # 1.8+ for provider-defined functions (provider::aws::arn_parse);
  # 6.0.0+ for the resource-level `region` argument.
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}
