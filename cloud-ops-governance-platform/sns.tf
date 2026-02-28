module "sns" {
  source  = "tfe.prasanth.com/prasanth/sns/aws"
  version = "v1.0.1"

  sns_name          = "ccops-notifications"
  kms_master_key_id = module.sns_kms.key_id
  topic_policy      = data.aws_iam_policy_document.sns_topic_policy.json

  subscriptions = [
    {
      endpoint = "Cloud_Operations_DL@prasanth.com"
      protocol = "email"
    }
  ]

  delivery_policy = file("${path.module}/iam/sns-topic-delivery-policy.json")

  application_feedback = {
    failure_role_arn    = module.sns_iam_role.iam_role_arn
    success_role_arn    = module.sns_iam_role.iam_role_arn
    success_sample_rate = 1
  }

  http_feedback = {
    failure_role_arn    = module.sns_iam_role.iam_role_arn
    success_role_arn    = module.sns_iam_role.iam_role_arn
    success_sample_rate = 1
  }
}

module "step_function_failure_topic" {
  source  = "tfe.prasanth.com/prasanth/sns/aws"
  version = "v1.0.1"

  sns_name          = "step-function-failure-notifications"
  kms_master_key_id = module.stepfunc_kms.key_id
  topic_policy      = data.aws_iam_policy_document.sns_stepfunc_policy_document.json

  subscriptions = [
    {
      endpoint = "@prasanth.com"
      protocol = "email"
    }
  ]
}