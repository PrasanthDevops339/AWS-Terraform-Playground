module "ecs_service" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  container_config = {
    app = {
      container_name = "app"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = var.log_group_name

        environment = [
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ]

        # Named port mappings are compatible with Service Connect if you add it
        # later. For a plain LB-backed service, the same mapping still works.
        port_mappings = [
          {
            name          = "http"
            containerPort = var.container_port
            hostPort      = var.container_port
            protocol      = "tcp"
            appProtocol   = "http"
          }
        ]
      }

      service = {
        desired_count                     = 1
        enable_execute_command            = true
        enable_ecs_managed_tags           = true
        health_check_grace_period_seconds = 60
        security_groups                   = [var.service_security_group_id]
        subnets                           = var.subnet_ids

        target_groups = [
          {
            target_group_arn = var.target_group_arn
            container_name   = "app"
            container_port   = var.container_port
          }
        ]
      }
    }
  }
}
