locals {
  platform_tags = {
    "managed-by" = "terraform"
    "module"     = "terraform-aws-cognito"
  }

  common_tags = merge(
    local.platform_tags,
    var.tags
  )
}
