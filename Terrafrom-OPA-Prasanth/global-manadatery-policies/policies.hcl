policy "mandatory_efs_encryption" {
  query = "data.terraform.policies.aws_efs_001_mandatory_encryption.deny"
  enforcement_level = "mandatory"
  description = "Enforce EFS KMS encryption at rest for all EFS file systems and replication destinations"
}
