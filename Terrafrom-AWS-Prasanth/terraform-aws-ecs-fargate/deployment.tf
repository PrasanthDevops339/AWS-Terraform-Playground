########################################
# CodeDeploy Application for Blue/Green Deployments
########################################

# CodeDeploy Application
resource "aws_codedeploy_app" "main" {
  for_each = {
    for k, v in var.container_config : k => v
    if try(v.service.deployment_controller.type, "ECS") == "CODE_DEPLOY"
  }

  compute_platform = "ECS"
  name             = "${local.account_alias}-${each.key}-codedeploy"
  tags             = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-codedeploy" })
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "main" {
  for_each = {
    for k, v in var.container_config : k => v
    if try(v.service.deployment_controller.type, "ECS") == "CODE_DEPLOY"
  }

  app_name              = aws_codedeploy_app.main[each.key].name
  deployment_group_name = "${local.account_alias}-${each.key}-dg"
  service_role_arn      = try(each.value.service.codedeploy_role_arn, null)

  auto_rollback_configuration {
    enabled = try(each.value.service.auto_rollback_configuration.enabled, true)
    events  = try(each.value.service.auto_rollback_configuration.events, ["DEPLOYMENT_FAILURE"])
  }

  dynamic "blue_green_deployment_config" {
    for_each = try(each.value.service.blue_green_deployment_config, null) != null ? [each.value.service.blue_green_deployment_config] : []
    content {
      terminate_blue_instances_on_deployment_success {
        action                         = try(blue_green_deployment_config.value.terminate_blue_instances_on_deployment_success.action, "TERMINATE")
        termination_wait_time_in_minutes = try(blue_green_deployment_config.value.terminate_blue_instances_on_deployment_success.termination_wait_time_in_minutes, 5)
      }

      deployment_ready_option {
        action_on_timeout = try(blue_green_deployment_config.value.deployment_ready_option.action_on_timeout, "CONTINUE_DEPLOYMENT")
        wait_time_in_minutes = try(blue_green_deployment_config.value.deployment_ready_option.wait_time_in_minutes, 0)
      }

      green_fleet_provisioning_option {
        action = try(blue_green_deployment_config.value.green_fleet_provisioning_option.action, "COPY_AUTO_SCALING_GROUP")
      }
    }
  }

  deployment_style {
    deployment_option = try(each.value.service.deployment_style.deployment_option, "WITH_TRAFFIC_CONTROL")
    deployment_type   = try(each.value.service.deployment_style.deployment_type, "BLUE_GREEN")
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main[0].name
    service_name = aws_ecs_service.main[each.key].name
  }

  dynamic "load_balancer_info" {
    for_each = var.load_balanced && length(var.target_groups) > 0 ? [1] : []
    content {
      dynamic "target_group_info" {
        for_each = var.target_groups
        content {
          name = try(target_group_info.value.name, null)
        }
      }
    }
  }

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-dg" })
}

########################################
# Deployment Controller Configuration
########################################

# Update ECS service to include deployment controller
resource "aws_ecs_service" "codedeploy" {
  for_each = {
    for k, v in var.container_config : k => v
    if try(v.service.deployment_controller.type, "ECS") == "CODE_DEPLOY"
  }

  name            = "${local.account_alias}-${each.key}-codedeploy"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.main[each.key].arn
  desired_count   = try(each.value.service.desired_count, 1)
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    security_groups = try(each.value.service.security_groups, [])
    subnets         = try(each.value.service.subnets, [])
    assign_public_ip = try(each.value.service.assign_public_ip, false)
  }

  # Load balancer configuration for CodeDeploy
  dynamic "load_balancer" {
    for_each = var.load_balanced ? var.target_groups : []
    content {
      container_name   = try(load_balancer.value.container_name, "${local.account_alias}-${each.key}-${var.container_name}")
      container_port   = lookup(load_balancer.value, "container_port", var.task_container_port)
      target_group_arn = lookup(load_balancer.value, "target_group_arn", null)
    }
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-codedeploy" })
}

########################################
# External Deployment Controller Support
########################################

# For external deployment controllers, create service without task definition management
resource "aws_ecs_service" "external" {
  for_each = {
    for k, v in var.container_config : k => v
    if try(v.service.deployment_controller.type, "ECS") == "EXTERNAL"
  }

  name          = "${local.account_alias}-${each.key}-external"
  cluster       = aws_ecs_cluster.main[0].id
  desired_count = try(each.value.service.desired_count, 1)
  launch_type   = "FARGATE"

  deployment_controller {
    type = "EXTERNAL"
  }

  network_configuration {
    security_groups = try(each.value.service.security_groups, [])
    subnets         = try(each.value.service.subnets, [])
    assign_public_ip = try(each.value.service.assign_public_ip, false)
  }

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-external" })
}