###########################
# Customer managed KMS key
###########################

resource "aws_kms_key" "main" {
  count                    = var.enable_creation == true && var.enable_replica != true && var.enable_region_argument != true ? 1 : 0
  description              = var.description
  enable_key_rotation      = true
  is_enabled               = var.enable_key
  multi_region             = true
  deletion_window_in_days  = var.deletion_window_in_days

  tags = merge(
    var.tags,
    tomap({ Name = "${local.account_alias}-${var.key_name}" })
  )
}

###########################################
# Assigns an alias name to the kms id using the account profile, followed by the key_name variable
###########################################

resource "aws_kms_alias" "main" {
  count         = var.enable_creation == true && var.enable_replica != true && var.enable_region_argument != true ? 1 : 0
  name          = "alias/${local.account_alias}-${var.key_name}"
  target_key_id = aws_kms_key.main[0].id
}

###########################################
# Customer managed KMS key replica to use for DR region
###########################################

resource "aws_kms_replica_key" "main" {
  count  = var.enable_creation == true && var.enable_replica == true && var.enable_region_argument != true ? 1 : 0
  region = var.secondary_region # This variable defaults to "us-east-1"

  description              = "replica key-${var.description}"
  primary_key_arn          = var.primary_key_arn
  deletion_window_in_days  = var.deletion_window_in_days

  tags = merge(
    var.tags,
    tomap({ Name = "${local.account_alias}-${var.key_name}" })
  )
}

###########################
# Alias Name for replica key
###########################

resource "aws_kms_alias" "replica" {
  count         = var.enable_creation == true && var.enable_replica == true && var.enable_region_argument != true ? 1 : 0
  name          = "alias/${local.account_alias}-${var.key_name}"
  target_key_id = aws_kms_replica_key.main[0].key_id
}

###########################
# KMS Key policy
###########################

resource "aws_kms_key_policy" "main" {
  count  = var.enable_creation == true && var.enable_region_argument != true ? 1 : 0
  key_id = var.enable_replica != true ? aws_kms_key.main[0].id : aws_kms_replica_key.main[0].key_id
  policy = local.kms_policy
}
