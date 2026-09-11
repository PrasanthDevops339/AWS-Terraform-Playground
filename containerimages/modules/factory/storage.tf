resource "aws_s3_bucket" "evidence" {
  #checkov:skip=CKV2_AWS_62:The release workflow explicitly records evidence; this bucket has no downstream event-notification consumer.
  #checkov:skip=CKV_AWS_144:The initial evidence store is regional and versioned; image replication does not imply a cross-region evidence disaster-recovery policy.

  bucket        = "${var.name}-${var.account_id}-${var.primary_region}"
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket                  = aws_s3_bucket.evidence.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.primary.arn
    }
  }
}
resource "aws_s3_bucket_policy" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid       = "RequireTLS", Effect = "Deny", Principal = "*", Action = "s3:*",
    Resource  = [aws_s3_bucket.evidence.arn, "${aws_s3_bucket.evidence.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
}
resource "aws_s3_bucket_lifecycle_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  rule {
    id     = "EvidenceRetention"
    status = "Enabled"
    filter {
      prefix = "releases/"
    }
    expiration {
      days = 400
    }
    noncurrent_version_expiration {
      noncurrent_days = 400
    }
  }
  rule {
    id     = "IncompleteUploads"
    status = "Enabled"
    filter {
      prefix = ""
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.evidence]
}
resource "aws_dynamodb_table" "releases" {
  name                        = "${var.name}-releases"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "pk"
  deletion_protection_enabled = true
  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "kind"
    type = "S"
  }
  global_secondary_index {
    name = "kind"
    key_schema {
      attribute_name = "kind"
      key_type       = "HASH"
    }
    projection_type = "ALL"
  }
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.primary.arn
  }
  lifecycle {
    prevent_destroy = true
  }
}
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../.build/lambda"
  output_path = "${path.module}/../../.build/lambda.zip"
}
data "archive_file" "promotion" {
  type        = "zip"
  source_dir  = "${path.module}/../../runtime"
  output_path = "${path.module}/../../.build/promotion.zip"
}
resource "aws_s3_object" "promotion" {
  bucket      = aws_s3_bucket.evidence.id
  key         = "automation/${data.archive_file.promotion.output_sha256}.zip"
  source      = data.archive_file.promotion.output_path
  source_hash = data.archive_file.promotion.output_sha256
  kms_key_id  = aws_kms_key.primary.arn
}

resource "aws_s3_bucket_logging" "evidence" {
  bucket        = aws_s3_bucket.evidence.id
  target_bucket = var.access_log_bucket_name
  target_prefix = "containerimages/${var.name}/"
}
