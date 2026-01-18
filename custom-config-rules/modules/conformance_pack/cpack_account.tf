resource "aws_config_conformance_pack" "account_main" {
  count = !var.organization_pack ? 1 : 0
  name  = "${local.account_alias}-${var.cpack_name}${local.random_id}"

  template_body = local.cpack_yml
}
