module "ccop_dynamodb_table" {
  source  = "tfe.prasanth.com/prasanth/dynamodb/aws"
  version = "1.1.3"

  db_table_name                 = "ccops-policy-engine-rules"
  range_key                     = "id"
  hash_key                      = "source"
  table_class                   = "STANDARD"
  stream_enabled                = false
  server_side_encryption_kms_key_arn = module.ccop_dynamodb_kms_key.key_arn
  deletion_protection_enabled   = false

  attributes = {
    source = "S"
    id     = "N"
  }

  tags = merge(
    local.patch_tags,
    local.backup_tags
  )
}

locals {
  rules_data = jsondecode(file("${path.module}/dynamo/rules.json"))
}

resource "aws_dynamodb_table_item" "ccop_dynamodb_table_item" {
  for_each   = local.rules_data
  table_name = module.ccop_dynamodb_table.dynamodb_table_id
  hash_key   = "source"
  range_key  = "id"

  item = <<ITEM
{
  "id": {"N": "${each.value.id}"},
  "source": {"S": "${each.value.source}"},
  "description": {"S": "${each.value.description}"},
  "enabled": {"BOOL": ${each.value.enabled}},
  "actions_policy": {"S": ${jsonencode(each.value.actions_policy)}},
  "ingest_policy": {"S": ${jsonencode(each.value.ingest_policy)}}
}
ITEM
}
