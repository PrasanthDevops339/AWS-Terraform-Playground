################################################################################
# Mixed Fargate and EC2 capacity on one cluster
#
# The realistic shape once a platform matures: a single cluster where each
# workload picks the capacity that suits it, rather than one cluster per
# launch type.
#
#   api          FARGATE            spiky, latency-sensitive, no instances to run
#   gpu_inference EC2               needs GPU instances Fargate cannot provide
#   batch        EC2 + Spot         interruption tolerant, cheapest capacity wins
#   node_agent   EC2 + DAEMON       one per instance, monitors the EC2 fleet only
#
# Note that node_agent's DAEMON scheduling covers the EC2 instances only.
# Fargate tasks have no instance to run a daemon on, which is the practical
# reason a monitoring sidecar has to be part of the Fargate task definition.
################################################################################

provider "aws" {
  region = var.region
}

locals {
  gpu_provider  = module.ecs.capacity_provider_names["gpu"]
  spot_provider = module.ecs.capacity_provider_names["spot"]
}

module "ecs" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-ecs"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # Fargate providers stay associated alongside the EC2 ones the module builds.
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # No cluster-wide default: every service states its own capacity, so nothing
  # lands on Spot or on GPU instances by accident.
  default_capacity_provider_strategy = []

  ec2_capacity_providers = {
    # GPU instances for inference. ECS advertises the GPU count as an instance
    # attribute, which the task definition can then require.
    gpu = {
      instance_type = "g5.xlarge"
      vpc_id        = var.vpc_id
      subnet_ids    = var.private_subnet_ids

      # GPU-enabled ECS-optimized AMI, which ships the NVIDIA drivers and the
      # container toolkit.
      ami_ssm_parameter = "/aws/service/ecs/optimized-ami/amazon-linux-2023/gpu/recommended/image_id"

      min_size = 0
      max_size = 4

      # GPU instances are expensive, so hold no spare capacity.
      managed_scaling_target_capacity = 100

      root_volume_size_gb = 100

      create_security_group = true
      security_group_egress_rules = [
        {
          description = "HTTPS for image pulls and telemetry"
          ip_protocol = "tcp"
          from_port   = 443
          to_port     = 443
          cidr_ipv4   = "0.0.0.0/0"
        },
      ]
    }

    spot = {
      vpc_id     = var.vpc_id
      subnet_ids = var.private_subnet_ids

      instance_types_override                  = ["c6i.xlarge", "c6a.xlarge", "c5.xlarge"]
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"

      min_size = 0
      max_size = 20

      create_security_group = true
      security_group_egress_rules = [
        {
          description = "HTTPS for image pulls and telemetry"
          ip_protocol = "tcp"
          from_port   = 443
          to_port     = 443
          cidr_ipv4   = "0.0.0.0/0"
        },
      ]
    }
  }

  container_config = {

    ##########################################################################
    # Fargate: the request-serving API. Blue/green because it is user-facing.
    ##########################################################################
    api = {
      container_name = "api"

      task_definition = {
        cpu                 = 1024
        memory              = 2048
        image               = var.api_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/api"

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
        launch_type     = "FARGATE"
        desired_count   = 3
        subnets         = var.private_subnet_ids
        security_groups = [var.service_security_group_id]

        deployment_configuration = {
          strategy                 = "BLUE_GREEN"
          bake_time_in_minutes     = 10
          ecs_alb_service_role_arn = var.ecs_alb_service_role_arn
        }

        target_groups = [
          {
            target_group_arn           = var.blue_target_group_arn
            container_name             = "api"
            container_port             = var.container_port
            alternate_target_group_arn = var.green_target_group_arn
            production_listener_rule   = var.production_listener_rule_arn
          },
        ]
      }

      autoscaling = {
        min_capacity = 3
        max_capacity = 30
        cpu_scaling_policy_configuration = {
          target_value = 55
        }
      }

      alarms = {
        enabled        = true
        sns_topic_arns = var.alarm_sns_topic_arns
      }
    }

    ##########################################################################
    # EC2: GPU inference. The clearest case for EC2 - Fargate has no GPUs.
    ##########################################################################
    gpu_inference = {
      container_name = "inference"

      task_definition = {
        network_mode        = "awsvpc"
        cpu                 = 4096
        memory              = 15000
        image               = var.inference_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/gpu-inference"

        # Only place this task on an instance that actually has a GPU.
        placement_constraints = [
          {
            type       = "memberOf"
            expression = "attribute:ecs.instance-type =~ g5.*"
          },
        ]

        port_mappings = [
          {
            name          = "grpc"
            containerPort = 8500
            protocol      = "tcp"
          },
        ]
      }

      service = {
        launch_type     = "EC2"
        desired_count   = 1
        subnets         = var.private_subnet_ids
        security_groups = [var.service_security_group_id]

        capacity_provider_strategy = [
          {
            capacity_provider = local.gpu_provider
            weight            = 1
          },
        ]

        deployment_configuration = {
          strategy = "ROLLING"
          # GPU capacity is scarce, so free a task before placing its
          # replacement rather than requiring a spare instance.
          minimum_healthy_percent = 0
          maximum_percent         = 100
        }
      }
    }

    ##########################################################################
    # EC2 + Spot: batch work that tolerates interruption.
    ##########################################################################
    batch = {
      container_name = "batch"

      task_definition = {
        network_mode        = "bridge"
        cpu                 = 2048
        memory              = 4096
        image               = var.batch_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/batch"
      }

      service = {
        launch_type   = "EC2"
        desired_count = 8

        capacity_provider_strategy = [
          {
            capacity_provider = local.spot_provider
            weight            = 1
          },
        ]

        # Pack tightly so instances drain and terminate as work completes.
        ordered_placement_strategy = [
          {
            type  = "binpack"
            field = "memory"
          },
        ]

        deployment_configuration = {
          strategy                = "ROLLING"
          minimum_healthy_percent = 0
          maximum_percent         = 200
        }
      }
    }

    ##########################################################################
    # EC2 + DAEMON: one agent per container instance.
    #
    # Covers the EC2 fleet only. Fargate tasks have no host to place a daemon
    # on, which is why Fargate workloads need the agent as a sidecar instead.
    ##########################################################################
    node_agent = {
      container_name = "node-agent"

      task_definition = {
        network_mode        = "host"
        memory              = 256
        image               = var.node_agent_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/node-agent"
      }

      service = {
        launch_type         = "EC2"
        scheduling_strategy = "DAEMON"

        deployment_configuration = {
          strategy                = "ROLLING"
          minimum_healthy_percent = 0
        }
      }
    }
  }

  load_balanced = true
  target_groups = []
}
