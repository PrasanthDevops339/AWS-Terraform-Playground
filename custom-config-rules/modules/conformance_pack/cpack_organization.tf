resource "aws_config_organization_conformance_pack" "organization_main" {
  count = var.organization_pack ? 1 : 0
  name  = "${local.account_alias}-${var.cpack_name}"

  template_body     = local.cpack_yml
  excluded_accounts = var.excluded_accounts
}
