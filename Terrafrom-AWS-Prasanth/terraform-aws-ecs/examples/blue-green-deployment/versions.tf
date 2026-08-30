terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Matches the module floor. LINEAR / CANARY and test_listener_rule
      # are not present in earlier 6.x releases.
      version = "~> 6.62"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
