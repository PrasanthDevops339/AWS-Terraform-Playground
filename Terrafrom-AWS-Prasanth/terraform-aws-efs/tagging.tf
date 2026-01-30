locals {
  module_version = split(" - ", split("## ", file("${path.module}/CHANGELOG.md"))[1])[0]

  platform_tags = {
    "platform:servicemodulename"    = "terraform-aws-efs"
    "platform:servicemoduleversion" = local.module_version
  }
}
