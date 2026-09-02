variable "account_id" {
  type = string
}

locals {
  # The Region the module's resources are pushed to, deliberately different
  # from the us-east-2 provider Region in version.tf. Kept as a local so the
  # module input and the aliased WAF provider can never drift apart.
  target_region = "us-east-1"
}
