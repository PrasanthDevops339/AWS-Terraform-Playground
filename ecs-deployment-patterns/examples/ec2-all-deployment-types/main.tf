################################################################################
# EC2 launch type - every deployment type ECS supports
#
# One cluster backed by two EC2 Auto Scaling group capacity providers, running
# eight services:
#
#   rolling_bridge  ECS / ROLLING      bridge network mode, instance target group
#   rolling_awsvpc  ECS / ROLLING      awsvpc network mode, task-level ENI
#   blue_green      ECS / BLUE_GREEN   full green fleet, bake, then cut
#   linear          ECS / LINEAR       25% of traffic every 2 minutes
#   canary          ECS / CANARY       5% canary, bake, then the rest
#   daemon          ECS / ROLLING      DAEMON scheduling - one task per instance
#   external        EXTERNAL           task sets managed outside Terraform
#   spot_batch      Spot capacity via a mixed-instances capacity provider
#
# Traffic shifting is done natively by ECS - no CodeDeploy anywhere.
#
# The two things that differ most from Fargate:
#
#   1. Capacity must exist. ec2_capacity_providers builds
#      launch template -> Auto Scaling group -> ECS capacity provider, and ECS
#      managed scaling then drives instance count from task demand.
#
#   2. Network mode is a real choice. bridge and host share the instance ENI
#      and register in target groups by instance; awsvpc gives each task its
#      own ENI and registers by IP, exactly like Fargate.
################################################################################

provider "aws" {
  region = var.region
}

locals {
  # Capacity provider names are "<account_alias>-<cluster_name>-<key>". Rather
  # than reconstruct that string, services below reference the module output.
  ondemand_provider = module.ecs.capacity_provider_names["ondemand"]
  spot_provider     = module.ecs.capacity_provider_names["spot"]

  port_mappings_awsvpc = [
    {
      name          = "http"
      containerPort = var.container_port
      protocol      = "tcp"
      appProtocol   = "http"
    },
  ]

  # hostPort 0 asks Docker for an ephemeral host port, which is what lets more
  # than one copy of a bridge-mode task share an instance.
  port_mappings_bridge = [
    {
      name          = "http"
      containerPort = var.container_port
      hostPort      = 0
      protocol      = "tcp"
      appProtocol   = "http"
    },
  ]
}

module "ecs" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-ecs"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  # Every service here is EC2 unless it says otherwise.
  launch_type_default = "EC2"

  # No Fargate providers on this cluster. EC2 provider names are appended by
  # the module automatically.
  capacity_providers = []

  # There is no cluster-wide default: each service names the provider it wants,
  # which keeps Spot placement explicit rather than accidental.
  default_capacity_provider_strategy = []

  ##############################################################################
  # EC2 capacity
  ##############################################################################

  ec2_capacity_providers = {
    # On-demand capacity for anything that serves traffic.
    ondemand = {
      instance_type = "m6i.large"
      vpc_id        = var.vpc_id
      subnet_ids    = var.private_subnet_ids

      min_size = 2
      max_size = 12

      # Target 100% means ECS keeps just enough instances for current task
      # demand. Lower it to hold spare capacity for faster scale-out.
      managed_scaling_target_capacity = 100

      # ECS marks instances running tasks as protected, so the ASG cannot
      # terminate them from under a running deployment.
      managed_termination_protection = "ENABLED"
      managed_draining               = "ENABLED"

      create_security_group = true
      security_group_ingress_rules = [
        {
          description = "Ephemeral host ports from the load balancer"
          ip_protocol = "tcp"
          from_port   = 32768
          to_port     = 65535
          # bridge-mode tasks are reached on the instance's ephemeral ports.
          referenced_security_group_id = var.alb_security_group_id
        },
        {
          description                  = "Container port for awsvpc tasks"
          ip_protocol                  = "tcp"
          from_port                    = var.container_port
          to_port                      = var.container_port
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

    # Spot capacity for interruption-tolerant work. A non-empty
    # instance_types_override switches the ASG to a mixed instances policy,
    # which is what diversifies Spot across pools.
    spot = {
      vpc_id     = var.vpc_id
      subnet_ids = var.private_subnet_ids

      instance_types_override = ["m6i.large", "m6a.large", "m5.large", "m5a.large"]

      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"

      min_size = 0
      max_size = 20

      # Rebalances ahead of a Spot interruption notice.
      capacity_rebalance = true

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
    # 1. ROLLING on the bridge network mode.
    #
    #    Tasks share the instance ENI and are registered in the target group
    #    by instance ID, so the target group must be target_type = "instance".
    ##########################################################################
    rolling_bridge = {
      container_name = "app"

      task_definition = {
        network_mode = "bridge"

        # On EC2, cpu/memory may be set per container rather than per task.
        # memoryReservation is a soft limit; memory is the hard cap.
        cpu               = 512
        memory            = 1024
        image             = var.container_image
        memoryReservation = 512

        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/rolling-bridge"
        port_mappings       = local.port_mappings_bridge
      }

      service = {
        launch_type   = "EC2"
        desired_count = 4

        capacity_provider_strategy = [
          {
            capacity_provider = local.ondemand_provider
            weight            = 1
          },
        ]

        health_check_grace_period_seconds = 90

        # Spread across AZs first, then pack by memory. Placement is EC2-only:
        # Fargate has no instances to place across.
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
          # 50/200 lets ECS free host ports before placing replacements, which
          # matters more on EC2 than Fargate because capacity is finite.
          minimum_healthy_percent = 50
          maximum_percent         = 200

          deployment_circuit_breaker = {
            enable   = true
            rollback = true
          }
        }

        target_groups = [
          {
            target_group_arn = var.instance_blue_target_group_arn
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

    ##########################################################################
    # 2. ROLLING on the awsvpc network mode.
    #
    #    Each task gets its own ENI and registers by IP, exactly like Fargate.
    #    Costs one ENI per task against the instance's ENI limit.
    ##########################################################################
    rolling_awsvpc = {
      container_name = "app"

      task_definition = {
        network_mode        = "awsvpc"
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/rolling-awsvpc"
        port_mappings       = local.port_mappings_awsvpc
      }

      service = {
        launch_type   = "EC2"
        desired_count = 2

        # awsvpc tasks need their own subnets and security groups, just as on
        # Fargate. bridge and host services must not set these.
        subnets         = var.private_subnet_ids
        security_groups = [var.service_security_group_id]

        capacity_provider_strategy = [
          {
            capacity_provider = local.ondemand_provider
            weight            = 1
          },
        ]

        deployment_configuration = {
          strategy                = "ROLLING"
          minimum_healthy_percent = 100
          maximum_percent         = 200
        }

        target_groups = [
          {
            target_group_arn = var.ip_blue_target_group_arn
            container_name   = "app"
            container_port   = var.container_port
          },
        ]
      }
    }

    ##########################################################################
    # 3. BLUE_GREEN on EC2. Identical to the Fargate form - the deployment
    #    strategy is independent of the launch type.
    ##########################################################################
    blue_green = {
      container_name = "app"

      task_definition = {
        network_mode        = "awsvpc"
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/blue-green"
        port_mappings       = local.port_mappings_awsvpc
      }

      service = {
        launch_type     = "EC2"
        desired_count   = 2
        subnets         = var.private_subnet_ids
        security_groups = [var.service_security_group_id]

        capacity_provider_strategy = [
          {
            capacity_provider = local.ondemand_provider
            weight            = 1
          },
        ]

        deployment_configuration = {
          strategy                 = "BLUE_GREEN"
          bake_time_in_minutes     = 10
          ecs_alb_service_role_arn = var.ecs_alb_service_role_arn

          alarms = {
            enable      = true
            rollback    = true
            alarm_names = var.rollback_alarm_names
          }
        }

        target_groups = [
          {
            target_group_arn           = var.ip_blue_target_group_arn
            container_name             = "app"
            container_port             = var.container_port
            alternate_target_group_arn = var.ip_green_target_group_arn
            production_listener_rule   = var.production_listener_rule_arn
            test_listener_rule         = var.test_listener_rule_arn
          },
        ]
      }
    }

    ##########################################################################
    # 4. LINEAR on EC2 - 25% of traffic every 2 minutes.
    ##########################################################################
    linear = {
      container_name = "app"

      task_definition = {
        network_mode        = "awsvpc"
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/linear"
        port_mappings       = local.port_mappings_awsvpc
      }

      service = {
        launch_type     = "EC2"
        desired_count   = 4
        subnets         = var.private_subnet_ids
        security_groups = [var.service_security_group_id]

        capacity_provider_strategy = [
          {
            capacity_provider = local.ondemand_provider
            weight            = 1
          },
        ]

        deployment_configuration = {
          strategy                 = "LINEAR"
          bake_time_in_minutes     = 5
          ecs_alb_service_role_arn = var.ecs_alb_service_role_arn

          linear_configuration = {
            step_percent              = 25
            step_bake_time_in_minutes = 2
          }
        }

        target_groups = [
          {
            target_group_arn           = var.ip_blue_target_group_arn
            container_name             = "app"
            container_port             = var.container_port
            alternate_target_group_arn = var.ip_green_target_group_arn
            production_listener_rule   = var.production_listener_rule_arn
          },
        ]
      }
    }

    ##########################################################################
    # 5. CANARY on EC2 - 5% for 20 minutes, then the remainder.
    ##########################################################################
    canary = {
      container_name = "app"

      task_definition = {
        network_mode        = "awsvpc"
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/canary"
        port_mappings       = local.port_mappings_awsvpc
      }

      service = {
        launch_type     = "EC2"
        desired_count   = 6
        subnets         = var.private_subnet_ids
        security_groups = [var.service_security_group_id]

        capacity_provider_strategy = [
          {
            capacity_provider = local.ondemand_provider
            weight            = 1
          },
        ]

        deployment_configuration = {
          strategy                 = "CANARY"
          bake_time_in_minutes     = 5
          ecs_alb_service_role_arn = var.ecs_alb_service_role_arn

          canary_configuration = {
            canary_percent              = 5
            canary_bake_time_in_minutes = 20
          }

          alarms = {
            enable      = true
            rollback    = true
            alarm_names = var.rollback_alarm_names
          }
        }

        target_groups = [
          {
            target_group_arn           = var.ip_blue_target_group_arn
            container_name             = "app"
            container_port             = var.container_port
            alternate_target_group_arn = var.ip_green_target_group_arn
            production_listener_rule   = var.production_listener_rule_arn
          },
        ]
      }
    }

    ##########################################################################
    # 6. DAEMON scheduling - one task on every container instance.
    #
    #    The deployment shape that only exists on EC2. Typical for log
    #    shippers, metrics agents and security sensors.
    #
    #    ECS rejects desired_count, deployment_maximum_percent, autoscaling and
    #    the CODE_DEPLOY / EXTERNAL controllers for DAEMON services; the module
    #    drops those arguments rather than letting the apply fail.
    ##########################################################################
    daemon = {
      container_name = "log-agent"

      task_definition = {
        # host lets the agent read the instance's own network stack.
        network_mode        = "host"
        memory              = 256
        image               = var.log_agent_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/daemon"

        # Read-only view of the Docker socket and the host log directory.
        bind_mount_volumes = [
          {
            name      = "docker-socket"
            host_path = "/var/run/docker.sock"
          },
          {
            name      = "host-logs"
            host_path = "/var/log"
          },
        ]

        mount_points = [
          {
            sourceVolume  = "docker-socket"
            containerPath = "/var/run/docker.sock"
            readOnly      = true
          },
          {
            sourceVolume  = "host-logs"
            containerPath = "/host/var/log"
            readOnly      = true
          },
        ]
      }

      service = {
        launch_type         = "EC2"
        scheduling_strategy = "DAEMON"

        # Deliberately no desired_count: ECS runs exactly one task per
        # instance and rejects a count.

        deployment_configuration = {
          strategy = "ROLLING"
          # Only the minimum applies to a DAEMON service.
          minimum_healthy_percent = 0
        }

        # Keep the agent off Spot instances, which disappear mid-flush.
        placement_constraints = [
          {
            type       = "memberOf"
            expression = "attribute:ecs.capacity-provider != ${local.spot_provider}"
          },
        ]
      }
    }

    ##########################################################################
    # 7. EXTERNAL controller on EC2.
    ##########################################################################
    external = {
      container_name = "app"

      task_definition = {
        network_mode        = "bridge"
        cpu                 = 256
        memory              = 512
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/external"
        port_mappings       = local.port_mappings_bridge
      }

      service = {
        launch_type   = "EC2"
        desired_count = 1

        deployment_controller = {
          type = "EXTERNAL"
        }
      }
    }

    ##########################################################################
    # 8. Batch work on Spot capacity.
    #
    #    Distinct from the interruption-sensitive services above: this one is
    #    pinned to the Spot capacity provider and expects to be restarted.
    ##########################################################################
    spot_batch = {
      container_name = "batch"

      task_definition = {
        network_mode        = "bridge"
        cpu                 = 1024
        memory              = 2048
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/spot-batch"
      }

      service = {
        launch_type   = "EC2"
        desired_count = 10

        capacity_provider_strategy = [
          {
            capacity_provider = local.spot_provider
            weight            = 1
          },
        ]

        # Pack tasks tightly so instances can be released as work drains.
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
  }

  load_balanced = true
  target_groups = []
}
