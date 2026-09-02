terraform {
  # 1.3+ for startswith(); 6.0.0+ for the resource-level `region` argument.
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}
