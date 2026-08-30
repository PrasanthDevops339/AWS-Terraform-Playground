########################################
# ecs-service-external.tf
#
# The EXTERNAL deployment controller.
#
# A third-party deployment system creates task sets through the CreateTaskSet
# API. ECS creates the service shell only: the task definition, networking and
# load balancer wiring all live on the task sets, not on the service.
#
# This lives in its own file rather than in ecs-service.tf because
# lifecycle.ignore_changes cannot be computed, so each deployment controller
# needs its own resource.
########################################

resource "aws_ecs_service" "external" {
  for_each = local.services_external

  name          = "${local.account_alias}-${each.key}"
  cluster       = local.cluster_id
  desired_count = try(each.value.service.desired_count, 1)

  propagate_tags          = try(each.value.service.propagate_tags, "SERVICE")
  enable_ecs_managed_tags = try(each.value.service.enable_ecs_managed_tags, true)

  deployment_controller {
    type = "EXTERNAL"
  }

  lifecycle {
    # The external system owns everything about the running tasks.
    ignore_changes = [desired_count]
  }

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}" })

  depends_on = [aws_ecs_cluster_capacity_providers.main]
}
