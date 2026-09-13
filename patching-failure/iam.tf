locals {
  # Built from inputs (not aws_iam_role.writer.arn) so it is known at plan time.
  writer_role_arn    = "arn:${local.partition}:iam::${local.account_id}:role${var.iam_role_path}${var.writer_role_name}"
  writer_arn_pattern = "arn:${local.partition}:iam::*:role${var.iam_role_path}${var.writer_role_name}"
  archive_object_arn = "arn:${local.partition}:s3:::${var.archive_bucket_name}/${var.archive_s3_prefix}/*"
  s3_actions         = var.archive_object_acl == null ? ["s3:PutObject"] : ["s3:PutObject", "s3:PutObjectAcl"]
  kms_actions        = ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"]

  central_condition = {
    StringEquals = { "aws:PrincipalOrgID" = var.organization_id }
    ArnLike      = { "aws:PrincipalArn" = local.writer_arn_pattern }
  }

  writer_policy = {
    Version = "2012-10-17"
    Statement = concat(
      [{ Sid = "S3WriteOnly", Effect = "Allow", Action = local.s3_actions, Resource = [local.archive_object_arn] }],
      var.archive_kms_key_arn == null ? [] : [{ Sid = "KmsEncryptOnly", Effect = "Allow", Action = local.kms_actions, Resource = [var.archive_kms_key_arn] }],
      var.enable_enrichment ? [{ Sid = "SsmReadOnly", Effect = "Allow", Action = ["ssm:ListCommandInvocations", "ssm:ListCommands", "ssm:DescribeInstanceInformation"], Resource = ["*"] }] : [],
      var.enable_enrichment && var.include_instance_tags ? [{ Sid = "Ec2DescribeForTags", Effect = "Allow", Action = ["ec2:DescribeInstances"], Resource = ["*"] }] : [],
    )
  }
}

# Lambda execution role. Its name must match the ArnLike pattern the central
# bucket/KMS policies authorize (see output central_prerequisites).
resource "aws_iam_role" "writer" {
  name                 = var.writer_role_name
  path                 = var.iam_role_path
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

# Central archive writes and optional SSM/EC2 enrichment reads.
resource "aws_iam_role_policy" "archive" {
  name   = "${var.writer_role_name}-archive"
  role   = aws_iam_role.writer.name
  policy = jsonencode(local.writer_policy)
}

# Runtime permissions for this function's own log group.
resource "aws_iam_role_policy" "runtime" {
  name = "${var.name_prefix}-${local.region}-runtime"
  role = aws_iam_role.writer.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs", Effect = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.this.arn}:*"]
      },
      # ENHANCEMENT (DLQ): uncomment with module.lambda_dlq in main.tf.
      # {
      #   Sid      = "LambdaFailureDestination", Effect = "Allow"
      #   Action   = ["sqs:SendMessage"]
      #   Resource = [module.lambda_dlq.queue_arn]
      # },
    ]
  })
}
