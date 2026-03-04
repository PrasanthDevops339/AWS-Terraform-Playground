module "ccop_ingest_reporting_bucket" {
  source  = "../../../environments/modules/s3/"
  version = "3.3.2"
  name    = "ccops-ingest"

  s3_bucket_name = "ccops-ingest"
  kms_key_arn    = module.ccop-s3-kms-key.key_arn

  ## Bucket policy
  policy_statements = [
    {
      principals = [
        {
          type        = "AWS"
          identifiers = ["*"]
        }
      ]

      actions = [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:PutObjectAcl",
        "s3:AbortMultipartUpload"
      ]

      effect = "Allow"

      resources = [
        "${module.ccop_ingest_reporting_bucket.bucket_arn}/*"
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:PrincipalOrgID"
          values   = ["o-1e70f219nn", "o-1e1yc82vv5"]
        },
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values   = ["arn:aws:iam::111111111111:role/prasanthins-loggerArchive-prd-backup-replication-role"]
        }
      ]
    }
  ]
}

## enable eventbridge notifications for the S3 bucket
resource "aws_s3_bucket_notification" "ccop_ingest_bucket-eventbridge-enable" {
  bucket      = module.ccop_ingest_reporting_bucket.bucket_name
  eventbridge = true
}
