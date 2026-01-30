locals {
  module_version = split(" ", split("\n", file("${path.module}/CHANGELOG.md"))[1])[0]

  platform_tags = {
    "platform:servicemodulename"    = "terraform-aws-kms"
    "platform:servicemoduleversion" = local.module_version
  }
}
