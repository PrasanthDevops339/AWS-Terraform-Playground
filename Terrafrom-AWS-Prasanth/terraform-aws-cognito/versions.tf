terraform {
  # `lifecycle { precondition }` needs 1.2+; `startswith()` in the WAF
  # association's scope check needs 1.3+.
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.0.0 floor: the resource-level `region` argument used throughout this
      # module is only supported by AWS provider 6.x (enhanced region support).
      version = ">= 6.0.0"
    }
  }
}
