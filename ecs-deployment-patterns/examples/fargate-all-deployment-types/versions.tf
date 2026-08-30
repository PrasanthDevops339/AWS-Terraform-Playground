terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.62 is the floor the module was schema-verified against. The LINEAR
      # and CANARY strategies and test_listener_rule set this floor.
      version = "~> 6.62"
    }
  }
}
