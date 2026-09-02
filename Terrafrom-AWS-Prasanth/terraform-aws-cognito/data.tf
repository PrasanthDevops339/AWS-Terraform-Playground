data "aws_caller_identity" "current" {}

data "aws_iam_account_alias" "current" {}

# Resolves to var.region when it is set, and to the provider's Region when it
# is null. That gives the module the Region its resources actually land in,
# which the WAF association preconditions in main.tf compare the Web ACL
# against. Comparing against var.region directly would miss the case where the
# caller leaves var.region null but points web_acl_arn at a Web ACL that
# terraform-aws-waf placed in a different Region via its own `region` input.
data "aws_region" "current" {
  region = var.region
}

data "local_file" "saml_metadata" {
  filename = var.samlmetadatafile
}
