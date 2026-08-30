################################################################################
# EC2 launch type
#
# The counterpart to examples/simple: the smallest configuration that runs
# tasks on EC2 container instances rather than Fargate.
#
# The difference from Fargate is capacity. Fargate has none to manage; EC2
# needs registered container instances before ECS can place a task. One entry
# in ec2_capacity_providers builds the whole chain:
#
#   launch template -> Auto Scaling group -> ECS capacity provider
#
# ECS managed scaling then drives instance count from task demand, and managed
# termination protection stops the ASG terminating an instance that is still
# running tasks.
#
# For the full EC2 deployment matrix - DAEMON scheduling, Spot, placement
# strategies, blue/green on EC2 - see
# ../../../../ecs-deployment-patterns/examples/ec2-all-deployment-types/
################################################################################

module "ecs_ec2" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # Applies to every service that does not set its own launch_type.
  launch_type_default = "EC2"

  # No Fargate providers on this cluster. The EC2 provider this module creates
  # is appended to the cluster association automatically.
  capacity_providers = []

  # Each service names the provider it wants, so nothing is placed by accident.
  default_capacity_provider_strategy = []

  ############################################################################
  # Container instance capacity
  ############################################################################

  ec2_capacity_providers = {
    default = {
      instance_type = var.instance_type
      vpc_id        = var.vpc_id
      subnet_ids    = var.subnet_ids

      min_size = var.min_size
      max_size = var.max_size

      # 100 means ECS keeps just enough instances for current task demand.
      # Lower it to hold spare capacity for faster scale-out.
      managed_scaling_target_capacity = 100

      # Both default to ENABLED; spelled out because they are the two settings
      # that keep a deployment from losing tasks to a scale-in.
      managed_termination_protection = "ENABLED"
      managed_draining               = "ENABLED"

      create_security_group = true

      security_group_ingress_rules = [
        {
          # bridge-mode tasks are reached on the instance's ephemeral ports,
          # not on the container port.
          description                  = "Ephemeral host ports from the load balancer"
          ip_protocol                  = "tcp"
          from_port                    = 32768
          to_port                      = 65535
          referenced_security_group_id = var.alb_security_group_id
        },
      ]

      security_group_egress_rules = [
        {
          description = "HTTPS for image pulls, SSM and telemetry"
          ip_protocol = "tcp"
          from_port   = 443
          to_port     = 443
          cidr_ipv4   = "0.0.0.0/0"
        },
      ]
    }
  }

  ############################################################################
  # Service
  ############################################################################

  container_config = {
    app = {
      container_name = "app"

      task_definition = {
        # bridge is the module default for EC2. Set "awsvpc" for a per-task
        # ENI, which behaves exactly like Fargate.
        network_mode = "bridge"

        # On EC2 these are optional at task level - containers may declare
        # their own limits instead. memoryReservation is the soft limit ECS
        # schedules against; memory is the hard cap.
        cpu               = 512
        memory            = 1024
        memoryReservation = 512

        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/app"

        port_mappings = [
          {
            name          = "http"
            containerPort = var.container_port
            # hostPort 0 asks Docker for an ephemeral port, which is what lets
            # several copies of this task share one instance. A fixed hostPort
            # caps you at one task per instance.
            hostPort    = 0
            protocol    = "tcp"
            appProtocol = "http"
          },
        ]
      }

      service = {
        launch_type   = "EC2"
        desired_count = 2

        capacity_provider_strategy = [
          {
            capacity_provider = module.ecs_ec2.capacity_provider_names["default"]
            weight            = 1
          },
        ]

        # bridge and host services share the container instance ENI, so they
        # must NOT set subnets or security_groups. Those are awsvpc-only.

        enable_execute_command            = true
        health_check_grace_period_seconds = 90

        # Placement is EC2-only. Spread across AZs first, then pack by memory
        # so instances can be released as load drops.
        ordered_placement_strategy = [
          {
            type  = "spread"
            field = "attribute:ecs.availability-zone"
          },
          {
            type  = "binpack"
            field = "memory"
          },
        ]

        deployment_configuration = {
          strategy = "ROLLING"

          # 50/200 rather than 100/200: EC2 capacity is finite, so ECS needs to
          # free host ports before it can place replacements.
          minimum_healthy_percent = 50
          maximum_percent         = 200

          deployment_circuit_breaker = {
            enable   = true
            rollback = true
          }
        }

        target_groups = [
          {
            # Must be target_type = "instance" for bridge and host network
            # modes. Use "ip" only for awsvpc.
            target_group_arn = var.target_group_arn
            container_name   = "app"
            container_port   = var.container_port
          },
        ]
      }

      autoscaling = {
        min_capacity = 2
        max_capacity = 20

        cpu_scaling_policy_configuration = {
          target_value = 65
        }
      }

      alarms = {
        enabled        = true
        sns_topic_arns = var.alarm_sns_topic_arns
      }
    }
  }
}
