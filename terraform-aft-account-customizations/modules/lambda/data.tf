
############################
# Get current account alias
############################
data "aws_iam_account_alias" "current" {}

############################
# Get current account region
############################
data "aws_region" "current" {}

############################
# Caller Identity - account details
############################
data "aws_caller_identity" "current" {}
