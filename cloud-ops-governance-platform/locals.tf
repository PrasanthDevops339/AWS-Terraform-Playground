locals {
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

locals {
  app_subnet_list = "${split(",", data.aws_ssm_parameter.subnet-app-ids.value)}"
  web_subnet_list = "${split(",", data.aws_ssm_parameter.subnet-web-ids.value)}"
  subnet_list     = "${split(",", data.aws_ssm_parameter.subnet-web-ids.value)}"
}

## Dynamodb patching and backup tags ##
locals {
  patch_tags = { "PatchGroup" : "asg" }

  backup_tags = {
    "ops:backupSchedule1" = "none"
    "ops:backupSchedule2" = "none"
    "ops:backupSchedule3" = "none"
    "ops:backupSchedule4" = "none"
    "ops:backupSchedule5" = "none"
    "ops:drSchedule1"     = "none"
    "ops:drSchedule2"     = "none"
    "ops:drSchedule3"     = "none"
    "ops:drSchedule4"     = "none"
    "ops:drSchedule5"     = "none"
  }
}

## dynamically create bootstrap bucket name.
locals {
  lambda_bucket_name = "${var.account_profile}-bootstrap-use2"
}

locals {
  splunk_layer_arn = "arn:aws:lambda:us-east-2:111111111111:layer:splunk-apm:863"
}