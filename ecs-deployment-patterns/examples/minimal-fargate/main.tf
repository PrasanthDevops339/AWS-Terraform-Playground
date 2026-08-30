################################################################################
# Minimal Fargate service
#
# The smallest configuration that produces a running service: one Fargate task,
# no load balancer, the default ROLLING strategy on the ECS controller.
#
# Start here, then read fargate-all-deployment-types for the rest.
################################################################################

provider "aws" {
  region = var.region
}

module "ecs" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-ecs"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # No load balancer, so no target groups to wire up.
  load_balanced = false

  container_config = {
    app = {
      container_name = "app"

      task_definition = {
        # Both are required on Fargate: the task is the billing unit.
        cpu    = 256
        memory = 512

        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/app"

        port_mappings = [
          {
            name          = "http"
            containerPort = 8080
            protocol      = "tcp"
          },
        ]
      }

      service = {
        # FARGATE is the module default; stated here for clarity.
        launch_type   = "FARGATE"
        desired_count = 1

        # Fargate always uses awsvpc, so subnets and security groups are
        # required. The subnets need a NAT or VPC endpoint route to pull images.
        subnets         = var.private_subnet_ids
        security_groups = [var.service_security_group_id]

        enable_execute_command = true
      }
    }
  }
}
