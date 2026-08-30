################################################################################
# External deployment controller
#
# With deployment_controller.type = "EXTERNAL", ECS creates only the service
# shell. Everything about the running tasks - which task definition, how many,
# which subnets, which target group - lives on TASK SETS created through the
# CreateTaskSet API, not on the service.
#
# That is why the service block below is nearly empty. Setting
# task_definition, network_configuration or load_balancer on an EXTERNAL
# service is rejected by ECS, and the module omits them for you.
#
# Use this when a third-party deployment system (Spinnaker, Argo, an in-house
# release tool) owns the rollout and Terraform should only own the service
# shell and its scaling boundaries.
################################################################################

module "ecs_external" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # No load balancer on the service - task sets carry that wiring.
  load_balanced = false

  container_config = {
    app = {
      container_name = "app"

      # Terraform still registers the task definition. The external system
      # chooses which revision to run by referencing it from a task set.
      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = var.log_group_name

        port_mappings = [
          {
            name          = "http"
            containerPort = var.container_port
            protocol      = "tcp"
            appProtocol   = "http"
          },
        ]
      }

      service = {
        deployment_controller = {
          type = "EXTERNAL"
        }

        # The service's desired count is the total across all task sets. The
        # module ignores changes to it, because the external system - or
        # Application Auto Scaling below - owns it after creation.
        desired_count = var.desired_count
      }

      # Autoscaling still works with the EXTERNAL controller: it adjusts the
      # service's desired count, and the external system decides how that is
      # distributed across task sets.
      autoscaling = {
        min_capacity = var.min_capacity
        max_capacity = var.max_capacity

        cpu_scaling_policy_configuration = {
          target_value = 70
        }
      }

      alarms = {
        enabled        = true
        sns_topic_arns = var.alarm_sns_topic_arns
      }
    }
  }
}

################################################################################
# An initial task set
#
# This is the piece the external system normally owns. It is included here so
# the example produces something that actually serves traffic, and so the shape
# of a task set is visible.
#
# In a real external-controller setup you would either:
#   - let the deployment system create and promote task sets, and drop this
#     resource entirely, or
#   - keep a bootstrap task set in Terraform and have the pipeline manage the
#     rest.
#
# Do not manage both from both places.
################################################################################

resource "aws_ecs_task_set" "initial" {
  count = var.create_initial_task_set ? 1 : 0

  service         = module.ecs_external.service_name["app"]
  cluster         = module.ecs_external.cluster_name
  task_definition = module.ecs_external.task_definition_arn["app"]

  launch_type      = "FARGATE"
  platform_version = "LATEST"

  # Networking lives here rather than on the service.
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.service_security_group_id]
    assign_public_ip = false
  }

  # As does load balancer attachment.
  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = "app"
      container_port   = var.container_port
    }
  }

  # PERCENT of the service's desired count that this task set should run.
  # A blue/green cutover driven externally moves this from 100 to 0 on the old
  # task set while raising the new one from 0 to 100.
  scale {
    unit  = "PERCENT"
    value = 100
  }

  # Blocks until the task set reaches STEADY_STATE, so a broken image fails the
  # apply rather than silently leaving a task set that never stabilises.
  wait_until_stable         = true
  wait_until_stable_timeout = "10m"

  # An external system creates newer task sets and shifts scale between them.
  # Terraform must not revert those decisions.
  lifecycle {
    ignore_changes = [scale, task_definition]
  }

  tags = var.tags
}
