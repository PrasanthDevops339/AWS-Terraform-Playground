locals {
  created_writer_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${var.iam_role_path}${var.writer_role_name}"
  writer_arn_pattern      = "arn:${data.aws_partition.current.partition}:iam::*:role${var.iam_role_path}${var.writer_role_name}"
  archive_object_arn      = "arn:${data.aws_partition.current.partition}:s3:::${var.archive_bucket_name}/${var.archive_s3_prefix}/*"
  s3_actions              = var.archive_object_acl == null ? ["s3:PutObject"] : ["s3:PutObject", "s3:PutObjectAcl"]
  kms_actions             = ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"]
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

# The first regional deployment owns the account-wide Lambda role.
# Further regions reuse its ARN and add only their regional runtime permissions.
resource "aws_iam_role" "writer" {
  count = var.create_writer_role ? 1 : 0

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

resource "aws_iam_role_policy" "archive" {
  count = var.create_writer_role ? 1 : 0

  name   = "${var.writer_role_name}-archive"
  role   = aws_iam_role.writer[0].id
  policy = jsonencode(local.writer_policy)
}
