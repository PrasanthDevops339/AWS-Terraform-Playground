# Organization-level conformance pack
resource "aws_config_organization_conformance_pack" "pack" {
  count = var.organization_pack ? 1 : 0

  name          = "${local.account_alias}-${var.cpack_name}${local.random_id}"
  template_body = local.cpack_yml

  excluded_accounts = var.excluded_accounts

  depends_on = [aws_organizations_organization.org]
}

# Check if organization exists
data "aws_organizations_organization" "org" {
  count = var.organization_pack ? 1 : 0
}

# Placeholder - assumes org already exists
resource "aws_organizations_organization" "org" {
  count = 0  # Set to 0 assuming org already exists
}
