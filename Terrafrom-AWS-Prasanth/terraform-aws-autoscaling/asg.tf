locals {
  account_alias = data.aws_iam_account_alias.current.account_alias

  patch_group_tags = var.enable_patch_group_asg ? { PatchGroup = "asg" } : {}

  asg_tags = [
    for k, v in merge(var.asg_tags, local.patch_group_tags) : {
      key   = k
      value = v
      # PatchGroup is only useful on the instances themselves, since that is what
      # Patch Manager targets, so it always propagates regardless of the module setting.
      propagate_at_launch = k == "PatchGroup" ? true : var.asg_tags_propagate_at_launch
    }
  ]
}

resource "aws_launch_template" "main" {
  count = var.create_lt ? 1 : 0

  name                   = "${local.account_alias}-${var.launch_template_name}"
  description            = var.template_description
  image_id               = var.ami_id
  region                 = var.region
  instance_type          = var.instance_type
  user_data              = var.user_data
  update_default_version = var.update_default_version

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.vpc_security_group_ids
    delete_on_termination       = true
  }

  dynamic "block_device_mappings" {
    for_each = var.block_device_mappings
    content {
      device_name  = block_device_mappings.value.device_name
      no_device    = try(block_device_mappings.value.no_device, null)
      virtual_name = try(block_device_mappings.value.virtual_name, null)

      dynamic "ebs" {
        for_each = flatten(try(block_device_mappings.value.ebs, []))
        content {
          delete_on_termination = try(ebs.value.delete_on_termination, null)
          encrypted             = true
          kms_key_id            = try(ebs.value.kms_key_id, var.kms_key_id)
          iops                  = try(ebs.value.iops, null)
          throughput            = try(ebs.value.throughput, null)
          snapshot_id           = try(ebs.value.snapshot_id, null)
          volume_size           = try(ebs.value.volume_size, null)
          volume_type           = try(ebs.value.volume_type, null)
        }
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  lifecycle {
    create_before_destroy = true
  }

  monitoring {
    enabled = var.enable_monitoring
  }

  dynamic "tag_specifications" {
    for_each = length(var.tag_specifications) > 0 ? var.tag_specifications : []
    content {
      resource_type = try(tag_specifications.value.resource_type, null)
      tags = merge(
        { Launch_Template_Name = "${local.account_alias}-${var.launch_template_name}" },
        try(tag_specifications.value.tags, {}),
        local.platform_tags
      )
    }
  }

  tags = merge(
    var.asg_tags,
    { Name = "${local.account_alias}-${var.launch_template_name}" },
    local.platform_tags
  )
}

resource "aws_autoscaling_group" "main" {
  count = var.create_asg ? 1 : 0

  name                      = "${local.account_alias}-${var.autoscaling_group_name}"
  region                    = var.region
  vpc_zone_identifier       = data.aws_subnets.main.ids
  desired_capacity          = var.desired_capacity
  max_size                  = var.max_size
  min_size                  = var.min_size
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  default_cooldown          = var.default_cooldown
  target_group_arns         = var.target_group_arns
  default_instance_warmup   = var.instance_warmup
  min_elb_capacity          = var.min_elb_capacity
  wait_for_elb_capacity     = var.wait_for_elb_capacity
  wait_for_capacity_timeout = var.wait_for_capacity_timeout

  launch_template {
    id      = aws_launch_template.main[0].id
    version = var.launch_template_version
  }

  enabled_metrics = var.enabled_metrics

  dynamic "initial_lifecycle_hook" {
    for_each = var.initial_lifecycle_hooks
    content {
      name                    = initial_lifecycle_hook.value.name
      default_result          = try(initial_lifecycle_hook.value.default_result, null)
      heartbeat_timeout       = try(initial_lifecycle_hook.value.heartbeat_timeout, null)
      lifecycle_transition    = initial_lifecycle_hook.value.lifecycle_transition
      notification_metadata   = try(initial_lifecycle_hook.value.notification_metadata, null)
      notification_target_arn = try(initial_lifecycle_hook.value.notification_target_arn, null)
      role_arn                = try(initial_lifecycle_hook.value.role_arn, null)
    }
  }

  dynamic "instance_refresh" {
    for_each = length(var.instance_refresh) > 0 ? [var.instance_refresh] : []
    content {
      strategy = instance_refresh.value.strategy
      triggers = try(instance_refresh.value.triggers, null)

      dynamic "preferences" {
        for_each = try([instance_refresh.value.preferences], [])
        content {
          checkpoint_delay             = try(preferences.value.checkpoint_delay, null)
          checkpoint_percentages       = try(preferences.value.checkpoint_percentages, null)
          instance_warmup              = try(preferences.value.instance_warmup, null)
          min_healthy_percentage       = try(preferences.value.min_healthy_percentage, null)
          max_healthy_percentage       = try(preferences.value.max_healthy_percentage, null)
          auto_rollback                = try(preferences.value.auto_rollback, null)
          scale_in_protected_instances = try(preferences.value.scale_in_protected_instances, null)
          skip_matching                = try(preferences.value.skip_matching, null)
          standby_instances            = try(preferences.value.standby_instances, null)
        }
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.account_alias}-${var.autoscaling_group_name}"
    propagate_at_launch = var.asg_tags_propagate_at_launch
  }

  dynamic "tag" {
    for_each = local.asg_tags
    content {
      key                 = tag.value["key"]
      value               = tag.value["value"]
      propagate_at_launch = tag.value["propagate_at_launch"]
    }
  }

  depends_on = [aws_launch_template.main]
}
