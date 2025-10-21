# ecs-service placeholder; add your service and load_balancer logic here
########################################
# ecs-service.tf
########################################

resource "aws_ecs_service" "main" {
  for_each = var.container_config

  name                  = "${local.account_alias}-${each.key}"
  cluster               = aws_ecs_cluster.main[0].id
  task_definition       = aws_ecs_task_definition.main[each.key].arn
  desired_count         = try(each.value.service.desired_count, 1)
  propagate_tags        = try(each.value.service.propagate_tags, "SERVICE")
  launch_type           = "FARGATE"
  platform_version      = try(each.value.service.platform_version, "LATEST")
  scheduling_strategy   = "REPLICA"
  enable_execute_command = try(each.value.service.enable_execute_command, false)
  force_new_deployment   = try(each.value.service.force_new_deployment, false)

  tags = merge(var.tags, {
    "Name" = "${local.account_alias}-${each.key}"
  })

  network_configuration {
    security_groups = try(each.value.service.security_groups, [])
    subnets         = try(each.value.service.subnets, [])
  }

  # Attach to an ALB/NLB target group when load balanced
  dynamic "load_balancer" {
    for_each = var.load_balanced ? var.target_groups : []
    content {
      container_name = (
        try(lookup(load_balancer.value, "container_name", ""), "") != ""
      ) ? lookup(load_balancer.value, "container_name", "")
        : "${local.account_alias}-${each.key}-${var.container_name}"

      container_port = lookup(load_balancer.value, "container_port", var.task_container_port)

      # Target Group must be provided by external ALB module. Pass its ARN here.
      target_group_arn = lookup(load_balancer.value, "target_group_arn", null)
    }
  }
}

########################################
# Target Groups must be created externally (e.g., ALB module)
########################################
