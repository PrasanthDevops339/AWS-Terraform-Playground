mock_provider "aws" {}
variables {
  organization_id = "o-abcdefghij"
}
run "approved_repository_requires_organization_and_trusted_writer" {
  command = apply
  variables {
    name        = "golden/test/al2023-base"
    kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/11111111-1111-1111-1111-111111111111"
    approved    = true
    writer_arns = ["arn:aws:iam::123456789012:role/publisher"]
    reader_arns = []
  }
  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Approved tags must remain immutable."
  }
  assert {
    condition     = one([for s in jsondecode(aws_ecr_repository_policy.this.policy).Statement : s if s.Sid == "OrganizationPull"]).Condition.StringEquals["aws:PrincipalOrgID"] == "o-abcdefghij"
    error_message = "Organization pull must have an explicit organization condition."
  }
  assert {
    condition     = one([for s in jsondecode(aws_ecr_repository_policy.this.policy).Statement : s if s.Sid == "OnlyTrustedWriters"]).Effect == "Deny"
    error_message = "Other identities must be denied publication."
  }
}

run "staging_has_no_organization_pull_grant" {
  command = apply
  variables {
    name        = "staging/test/al2023-base"
    kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/11111111-1111-1111-1111-111111111111"
    approved    = false
    writer_arns = ["arn:aws:iam::123456789012:role/builder"]
    reader_arns = ["arn:aws:iam::123456789012:role/builder", "arn:aws:iam::123456789012:role/publisher"]
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_ecr_repository_policy.this.policy).Statement : s.Effect == "Deny"])
    error_message = "Staging must not grant organization-wide access."
  }
}
