resource "aws_ecs_cluster" "main" {
  count = var.create_cluster ? 1 : 0
  name  = "${local.account_alias}-${var.cluster_name}"

  dynamic "configuration" {
    for_each = length(var.cluster_configuration) > 0 ? var.cluster_configuration : []
    content {
      dynamic "execute_command_configuration" {
        for_each = try(configuration.value.execute_command_configuration, [{}])
        content {
          kms_key_id = try(execute_command_configuration.value.kms_key_id, null)
          logging    = try(execute_command_configuration.value.logging, "DEFAULT")

          dynamic "log_configuration" {
            for_each = try(execute_command_configuration.value.log_configuration, [{}])
            content {
              cloud_watch_encryption_enabled = try(log_configuration.value.cloud_watch_encryption_enabled, null)
              cloud_watch_log_group_name     = try(log_configuration.value.cloud_watch_log_group_name, null)
              s3_bucket_name                 = try(log_configuration.value.s3_bucket_name, null)
              s3_bucket_encryption_enabled   = try(log_configuration.value.s3_bucket_encryption_enabled, null)
              s3_key_prefix                  = try(log_configuration.value.s3_key_prefix, null)
            }
          }
        }
      }
    }
  }

  dynamic "setting" {
    for_each = flatten([var.cluster_settings])
    content {
      name  = setting.value.name
      value = setting.value.value
    }
  }

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${var.cluster_name}" })
}
