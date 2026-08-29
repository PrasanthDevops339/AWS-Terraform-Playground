terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Floor raised to 6.0.0 by the shared terraform-aws-sqs module, which
      # declares >= 6.0.0. The shared terraform-aws-lambda module needs the
      # archive provider transitively.
      version = ">= 6.0.0, < 7.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0, < 3.0.0"
    }
  }
}
