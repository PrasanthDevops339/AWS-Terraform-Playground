
#------------------------------
# LAMBDA FUNCTION - IAM Resources
#------------------------------

# Data source for lambda function - assume role policy
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    sid    = "LambdaAssumedRole"
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Create IAM Role for Lambda function
resource "aws_iam_role" "lambda" {
  count = var.create_lambda_function && var.lambda_role_arn == null ? 1 : 0

  name                 = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-lambda-role${local.workspace_string}"
  assume_role_policy   = local.assume_role_policy
  permissions_boundary = var.boundary_permissions_policy

  tags = merge(
    {
      "Name" = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-lambda-role${local.workspace_string}"
    },
    var.tags
  )
}

# Attach AWS managed policy for basic logging
resource "aws_iam_role_policy_attachment" "basic" {
  count      = var.create_lambda_function && var.lambda_role_arn == null ? 1 : 0
  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# If using VPC config, attach VPC access policy
resource "aws_iam_role_policy_attachment" "vpc" {
  count = var.create_lambda_function && var.lambda_role_arn == null && var.vpc_subnet_ids != null && var.vpc_security_group_ids != null ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Create IAM inline policy for Lambda function
resource "aws_iam_role_policy" "lambda_iam_role" {
  count = var.create_lambda_function && var.lambda_role_arn == null ? 1 : 0

  name   = "${data.aws_iam_account_alias.current.account_alias}-${var.lambda_name}-lambda-policy${local.workspace_string}"
  role   = aws_iam_role.lambda[0].name
  policy = var.policy_document
}
