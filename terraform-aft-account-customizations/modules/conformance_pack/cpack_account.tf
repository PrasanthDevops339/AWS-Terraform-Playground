# Account-level conformance pack (AFT deploys to each account individually)
resource "aws_config_conformance_pack" "pack" {
  name          = "${local.account_alias}-${var.cpack_name}${local.random_id}"
  template_body = local.cpack_yml

  # Conformance packs require an active Config recorder
  depends_on = [
    data.aws_config_configuration_recorder.existing
  ]
}
