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

  # Service Connect configuration
  dynamic "service_connect_defaults" {
    for_each = var.service_connect_configuration.enabled ? [var.service_connect_configuration] : []
    content {
      namespace = service_connect_defaults.value.namespace
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

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  count        = var.create_cluster ? 1 : 0
  cluster_name = aws_ecs_cluster.main[0].name

  capacity_providers = var.capacity_providers

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      base              = default_capacity_provider_strategy.value.base
      weight            = default_capacity_provider_strategy.value.weight
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
    }
  }
}
