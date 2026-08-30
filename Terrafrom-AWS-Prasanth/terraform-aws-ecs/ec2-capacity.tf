########################################
# ec2-capacity.tf
#
# EC2 container instance capacity for the EC2 launch type.
#
#   launch template -> Auto Scaling group -> ECS capacity provider
#
# ECS managed scaling drives the ASG desired capacity from task demand, and
# managed termination protection stops the ASG from terminating an instance
# that is still running tasks.
#
# Nothing in this file is created for a Fargate-only cluster - every resource
# is keyed off var.ec2_capacity_providers, which defaults to {}.
########################################

########################################
# Container instance IAM
########################################

data "aws_iam_policy_document" "ec2_instance_assume_role" {
  count = length(var.ec2_capacity_providers) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_instance" {
  count = length(var.ec2_capacity_providers) > 0 ? 1 : 0

  name               = "${local.cluster_name_full}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_instance_assume_role[0].json

  tags = merge(var.tags, { "Name" = "${local.cluster_name_full}-instance" })
}

# Lets the ECS agent register the instance with the cluster and poll for work.
resource "aws_iam_role_policy_attachment" "ec2_instance_ecs" {
  count = length(var.ec2_capacity_providers) > 0 ? 1 : 0

  role       = aws_iam_role.ec2_instance[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Required for ECS Exec and for SSM access to the instance itself.
resource "aws_iam_role_policy_attachment" "ec2_instance_ssm" {
  count = length(var.ec2_capacity_providers) > 0 ? 1 : 0

  role       = aws_iam_role.ec2_instance[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance" {
  count = length(var.ec2_capacity_providers) > 0 ? 1 : 0

  name = "${local.cluster_name_full}-instance"
  role = aws_iam_role.ec2_instance[0].name

  tags = merge(var.tags, { "Name" = "${local.cluster_name_full}-instance" })
}

########################################
# Container instance security group
########################################

resource "aws_security_group" "ec2_instance" {
  for_each = local.ec2_capacity_provider_sgs

  name_prefix = "${local.cluster_name_full}-${each.key}-"
  description = "ECS container instances for capacity provider ${local.ec2_capacity_provider_names[each.key]}"
  vpc_id      = each.value.vpc_id

  tags = merge(var.tags, {
    "Name" = "${local.cluster_name_full}-${each.key}-instance"
  })

  # The launch template references this group, so a replacement must exist
  # before the original can be destroyed.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_instance" {
  for_each = local.ec2_instance_ingress_rules

  security_group_id = aws_security_group.ec2_instance[each.value.cp_key].id
  description       = each.value.description
  ip_protocol       = each.value.ip_protocol

  # Port range must be omitted when the protocol is "all".
  from_port = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port   = each.value.ip_protocol == "-1" ? null : each.value.to_port

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "ec2_instance" {
  for_each = local.ec2_instance_egress_rules

  security_group_id = aws_security_group.ec2_instance[each.value.cp_key].id
  description       = each.value.description
  ip_protocol       = each.value.ip_protocol

  from_port = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port   = each.value.ip_protocol == "-1" ? null : each.value.to_port

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id

  tags = var.tags
}

########################################
# Launch template
########################################

resource "aws_launch_template" "ec2" {
  for_each = var.ec2_capacity_providers

  name_prefix = "${local.cluster_name_full}-${each.key}-"
  description = "ECS container instances for ${local.ec2_capacity_provider_names[each.key]}"

  image_id      = coalesce(each.value.ami_id, try(data.aws_ssm_parameter.ecs_ami[each.key].value, null))
  instance_type = each.value.instance_type
  key_name      = each.value.key_name

  # Writing ECS_CLUSTER into ecs.config is what makes the instance join the
  # cluster. Everything the caller supplies runs after that.
  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail
    echo "ECS_CLUSTER=${local.cluster_name_full}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_SPOT_INSTANCE_DRAINING=true" >> /etc/ecs/ecs.config
    ${each.value.additional_user_data}
  EOT
  )

  iam_instance_profile {
    arn = coalesce(each.value.instance_profile_arn, try(aws_iam_instance_profile.ec2_instance[0].arn, null))
  }

  vpc_security_group_ids = concat(
    each.value.security_group_ids,
    each.value.create_security_group ? [aws_security_group.ec2_instance[each.key].id] : [],
  )

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = each.value.root_volume_size_gb
      volume_type           = each.value.root_volume_type
      encrypted             = each.value.root_volume_encrypted
      kms_key_id            = each.value.root_volume_kms_key_id
      delete_on_termination = true
    }
  }

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = each.value.metadata_http_tokens
    http_put_response_hop_limit = each.value.metadata_http_put_response_hop_limit
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = each.value.enable_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      "Name" = "${local.cluster_name_full}-${each.key}"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }

  tags = merge(var.tags, { "Name" = "${local.cluster_name_full}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

########################################
# Auto Scaling group - single instance type
########################################

resource "aws_autoscaling_group" "ec2" {
  for_each = local.ec2_capacity_providers_single

  name_prefix         = "${local.cluster_name_full}-${each.key}-"
  vpc_zone_identifier = each.value.subnet_ids

  min_size         = each.value.min_size
  max_size         = each.value.max_size
  desired_capacity = each.value.desired_capacity

  health_check_type         = "EC2"
  health_check_grace_period = each.value.health_check_grace_period
  capacity_rebalance        = each.value.capacity_rebalance

  # Required by ECS managed termination protection - ECS sets per-instance
  # scale-in protection on instances that are running tasks.
  protect_from_scale_in = each.value.managed_termination_protection == "ENABLED"

  launch_template {
    id      = aws_launch_template.ec2[each.key].id
    version = aws_launch_template.ec2[each.key].latest_version
  }

  # Once the capacity provider is attached, ECS managed scaling owns
  # desired_capacity; without this every plan would try to reset it.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }

  dynamic "tag" {
    for_each = merge(var.tags, {
      "Name" = "${local.cluster_name_full}-${each.key}"
      # Required by ECS managed termination protection.
      "AmazonECSManaged" = "true"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

########################################
# Auto Scaling group - mixed instances / Spot
########################################

resource "aws_autoscaling_group" "ec2_mixed" {
  for_each = local.ec2_capacity_providers_mixed

  name_prefix         = "${local.cluster_name_full}-${each.key}-"
  vpc_zone_identifier = each.value.subnet_ids

  min_size         = each.value.min_size
  max_size         = each.value.max_size
  desired_capacity = each.value.desired_capacity

  health_check_type         = "EC2"
  health_check_grace_period = each.value.health_check_grace_period
  capacity_rebalance        = each.value.capacity_rebalance
  protect_from_scale_in     = each.value.managed_termination_protection == "ENABLED"

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = each.value.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = each.value.on_demand_percentage_above_base_capacity
      spot_allocation_strategy                 = each.value.spot_allocation_strategy
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ec2[each.key].id
        version            = aws_launch_template.ec2[each.key].latest_version
      }

      # Diversifying across instance types is what makes Spot capacity durable.
      dynamic "override" {
        for_each = each.value.instance_types_override
        content {
          instance_type = override.value
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }

  dynamic "tag" {
    for_each = merge(var.tags, {
      "Name"             = "${local.cluster_name_full}-${each.key}"
      "AmazonECSManaged" = "true"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

########################################
# ECS capacity provider
########################################

resource "aws_ecs_capacity_provider" "ec2" {
  for_each = var.ec2_capacity_providers

  name = local.ec2_capacity_provider_names[each.key]

  auto_scaling_group_provider {
    auto_scaling_group_arn = (
      length(each.value.instance_types_override) > 0
      ? aws_autoscaling_group.ec2_mixed[each.key].arn
      : aws_autoscaling_group.ec2[each.key].arn
    )

    # Drains tasks off an instance before the ASG terminates it.
    managed_draining               = each.value.managed_draining
    managed_termination_protection = each.value.managed_termination_protection

    managed_scaling {
      status                    = each.value.managed_scaling_status
      target_capacity           = each.value.managed_scaling_target_capacity
      minimum_scaling_step_size = each.value.managed_scaling_min_step_size
      maximum_scaling_step_size = each.value.managed_scaling_max_step_size
      instance_warmup_period    = each.value.managed_scaling_instance_warmup
    }
  }

  tags = merge(var.tags, { "Name" = local.ec2_capacity_provider_names[each.key] })
}
