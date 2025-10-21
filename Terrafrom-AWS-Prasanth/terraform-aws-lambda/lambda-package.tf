# LAMBDA FUNCTION - Source Code Package

# Data source to archive raw python file (or a dir) into a zip
data "archive_file" "rendered_zip" {
  count       = var.create_lambda_function == true && var.upload_to_s3 == true ? 1 : 0
  type        = "zip"
  output_path = "${var.lambda_name}.zip"

  # If a single in-memory script is supplied, add it as <lambda_name>.py
  dynamic "source" {
    for_each = var.lambda_script != null ? [true] : []
    content {
      content  = var.lambda_script
      filename = "${var.lambda_name}.py"
    }
  }

  # Or zip the provided source directory
  source_dir = var.lambda_script_dir
}

# Resource to create S3 object for the packaged zip
resource "aws_s3_object" "main" {
  count = var.create_lambda_function == true && var.upload_to_s3 == true ? 1 : 0

  source      = data.archive_file.rendered_zip.*.output_path[0]
  bucket      = var.lambda_bucket_name
  key         = var.lambda_name
  source_hash = data.archive_file.rendered_zip.*.output_base64sha256[0]

  tags = merge(
    var.package_tags,
    {
      Name         = "${var.lambda_bucket_key}"
      S3ObjectType = "LambdaPackage"
    }
  )

  # Ensure provider default_tags don't get applied to this object
  override_provider {
    default_tags {
      tags = {}
    }
  }
}
