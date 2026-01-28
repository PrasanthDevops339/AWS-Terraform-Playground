# Lambda-based AWS Config Custom Rule Module
# 
# WHY THIS MODULE EXISTS:
# Deploys Python Lambda functions as AWS Config custom rules when validation requires:
# - AWS API calls to retrieve data not in Config items (e.g., resource policies)
# - Complex logic beyond Guard DSL (JSON parsing, conditional evaluation)
# - Runtime queries to other AWS services
# - Custom compliance logic that Guard policy language cannot express
#
# COMPONENTS CREATED:
# - Lambda function (Python 3.12) with Config rule evaluation logic
# - IAM execution role with least privilege permissions
# - Lambda permission for Config service to invoke function
# - AWS Config rule (organization-wide OR account-level)
# - S3 bucket for Lambda deployment package

resource "aws_lambda_permission" "lambda_perm" {
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.lambda_function_name
  principal     = "config.amazonaws.com"
  statement_id  = "AllowExecutionFromConfig"
  depends_on    = [module.lambda]
}

module "lambda" {
  source  = "tfe.com/erie-insurance/lambda/aws"
  version = "1.3.6"

  upload_to_s3      = true
  lambda_role_arn   = module.lambda_role.iam_role_arn
  lambda_name       = var.random_id != null ? "${var.config_rule_name}-${var.random_id}" : var.config_rule_name
  runtime           = "python3.12"
  lambda_script_dir = var.lambda_script_dir
  lambda_bucket_name = data.aws_s3_bucket.bootstrap.id

  test_events = var.test_events

  environment = {
    Hello      = "World"
    Serverless = "Terraform"
  }
}

module "lambda_role" {
  source  = "tfe.com/erie-insurance/iam/aws"
  version = "2.0.0"

  trusted_role_services = ["lambda.amazonaws.com"]

  create_policy = true
  role_name     = var.config_rule_name
  description   = "lambda policy which will be assume by deployment account"
  policy_name   = var.config_rule_name
  policy        = file("${path.module}/iam/lambda_policy.json")
}

module "additional_policies" {
  count   = length(var.additional_policies)
  source  = "tfe.com/erie-insurance/iam/aws"
  version = "2.0.0"

  create_policy = true
  create_role   = false
  policy_name   = "${var.config_rule_name}-${count.index}"
  policy        = var.additional_policies[count.index]
}

resource "aws_iam_role_policy_attachment" "additional_policies_attachments" {
  count      = length(var.additional_policies)
  role       = module.lambda_role.iam_role_name
  policy_arn  = module.additional_policies[count.index].iam_policy_arn
}
