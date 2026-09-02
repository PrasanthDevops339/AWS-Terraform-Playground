data "aws_caller_identity" "current" {}

data "aws_iam_account_alias" "current" {}

# Resolves to var.region when set, the provider's Region when null.
data "aws_region" "current" {
  region = var.region
}

data "local_file" "saml_metadata" {
  filename = var.samlmetadatafile
}
