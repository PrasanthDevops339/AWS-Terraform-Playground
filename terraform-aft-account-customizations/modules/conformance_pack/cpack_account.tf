# Account-level conformance pack
resource "aws_config_conformance_pack" "pack" {
  count = var.organization_pack ? 0 : 1

  name          = "${local.account_alias}-${var.cpack_name}${local.random_id}"
  template_body = local.cpack_yml

  depends_on = [aws_config_configuration_recorder.recorder]
}

# Ensure Config recorder exists
resource "aws_config_configuration_recorder" "recorder" {
  count = var.organization_pack ? 0 : 1

  name     = "default"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported = true
  }
}

resource "aws_iam_role" "config" {
  count = var.organization_pack ? 0 : 1

  name = "${local.account_alias}-config-role${local.random_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/ConfigRole"
  ]

  tags = var.tags
}

resource "aws_config_configuration_recorder_status" "recorder" {
  count = var.organization_pack ? 0 : 1

  name       = aws_config_configuration_recorder.recorder[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.channel]
}

resource "aws_config_delivery_channel" "channel" {
  count = var.organization_pack ? 0 : 1

  name           = "default"
  s3_bucket_name = aws_s3_bucket.config[0].id

  depends_on = [aws_config_configuration_recorder.recorder]
}

resource "aws_s3_bucket" "config" {
  count = var.organization_pack ? 0 : 1

  bucket = "${local.account_alias}-config-bucket${local.random_id}"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "config" {
  count = var.organization_pack ? 0 : 1

  bucket = aws_s3_bucket.config[0].id

  versioning_configuration {
    status = "Enabled"
  }
}
