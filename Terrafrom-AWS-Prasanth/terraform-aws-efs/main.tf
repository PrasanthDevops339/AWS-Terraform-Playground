# PLACEHOLDER: module main.tf not provided in screenshots.
locals {
  efs_policy = (var.efs_file_system_policy != null ?
    data.aws_iam_policy_document.combined.json :
    data.aws_iam_policy_document.baseline.json
  )

  account_alias = data.aws_iam_account_alias.current.account_alias
}

# ------ File System ------ #

resource "aws_efs_file_system" "main" {

  availability_zone_name          = var.availability_zone_name
  creation_token                 = var.creation_token
  performance_mode               = var.performance_mode
  encrypted                      = true
  kms_key_id                     = var.kms_key_arn
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null
  throughput_mode                = var.throughput_mode

  # ------ Lifecycle Policy ------ #

  dynamic "lifecycle_policy" {
    for_each = length(var.lifecycle_policy.transition_to_ia) > 0 ? [1] : []
    content {
      transition_to_ia = try(var.lifecycle_policy.transition_to_ia[0], null)
    }
  }

  dynamic "lifecycle_policy" {
    for_each = length(var.lifecycle_policy.transition_to_archive) > 0 ? [1] : []
    content {
      transition_to_archive = try(var.lifecycle_policy.transition_to_archive[0], null)
    }
  }

  dynamic "lifecycle_policy" {
    for_each = length(var.lifecycle_policy.transition_to_primary_storage_class) > 0 ? [1] : []
    content {
      transition_to_primary_storage_class = try(var.lifecycle_policy.transition_to_primary_storage_class[0], null)
    }
  }

  protection {
    replication_overwrite = var.replication_overwrite
  }

  tags = merge(var.tags, { "Name" : "${local.account_alias}-${var.name}" }, local.platform_tags)
}

# ------ file system policy ------ #

resource "aws_efs_file_system_policy" "main" {

  file_system_id                   = aws_efs_file_system.main.id
  bypass_policy_lockout_safety_check = var.bypass_policy_lockout_safety_check
  policy                           = local.efs_policy
}

# ------ mount target ------ #

resource "aws_efs_mount_target" "main" {

  count = length(var.mount_targets.subnets)

  file_system_id  = aws_efs_file_system.main.id
  ip_address      = var.mount_target_ip_address
  security_groups = var.mount_targets.security_group_id
  subnet_id       = var.mount_targets.subnets[count.index]
}

# ------ access point ------ #

resource "aws_efs_access_point" "main" {

  for_each = { for k, v in var.access_points : k => v }

  file_system_id = aws_efs_file_system.main.id

  dynamic "posix_user" {
    for_each = try([each.value.posix_user], [])
    content {
      gid           = posix_user.value.gid
      uid           = posix_user.value.uid
      secondary_gids = try(posix_user.value.secondary_gids, null)
    }
  }

  dynamic "root_directory" {
    for_each = try([each.value.root_directory], [])
    content {
      path = try(root_directory.value.path, null)

      dynamic "creation_info" {
        for_each = try([root_directory.value.creation_info], [])
        content {
          owner_gid   = creation_info.value.owner_gid
          owner_uid   = creation_info.value.owner_uid
          permissions = creation_info.value.permissions
        }
      }
    }
  }

  tags = merge(var.tags, { "Name" : "${local.account_alias}-${var.name}" }, local.platform_tags)
}

# ------ Backup Policy ------ #

resource "aws_efs_backup_policy" "main" {

  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = var.enable_backup_policy ? "ENABLED" : "DISABLED"
  }
}

# ------ Replication Configuration ------ #

resource "aws_efs_replication_configuration" "main" {

  count = length(var.replication_configuration_destination)

  source_file_system_id = aws_efs_file_system.main.id

  dynamic "destination" {
    for_each = [var.replication_configuration_destination[count.index]]

    content {
      availability_zone_name = try(destination.value.availability_zone_name, null)
      kms_key_id             = try(destination.value.kms_key_id, null)
      region                 = try(destination.value.region, null)
    }
  }
}
