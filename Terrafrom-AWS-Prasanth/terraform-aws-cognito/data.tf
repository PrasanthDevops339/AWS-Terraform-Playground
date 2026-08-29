data "aws_caller_identity" "current" {}

data "aws_iam_account_alias" "current" {}

data "local_file" "saml_metadata" {
  count = var.saml_metadata_content == null ? 1 : 0

  filename = var.samlmetadatafile
}
