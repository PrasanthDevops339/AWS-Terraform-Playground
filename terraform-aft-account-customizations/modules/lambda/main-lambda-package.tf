
#--------------------------------
# LAMBDA FUNCTION - Packaging
#--------------------------------

resource "random_uuid" "key" {
  keepers = {
    lambda_name = var.lambda_name
    workspace   = var.workspace
  }
}

# Render zip from local folder (only if image_uri is not used)
data "archive_file" "rendered_zip" {
  count       = var.image_uri == null ? 1 : 0
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/zip/${var.lambda_name}-${random_uuid.key.result}.zip"
}

# Optionally upload package to S3 (for larger packages / central storage)
resource "aws_s3_object" "lambda_package_object" {
  count = var.upload_to_s3 ? 1 : 0

  bucket = var.lambda_bucket_name
  key    = "${var.lambda_name}/${random_uuid.key.result}.zip"

  source      = data.archive_file.rendered_zip[0].output_path
  source_hash = data.archive_file.rendered_zip[0].output_base64sha256

  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn

  tags = var.tags
}
