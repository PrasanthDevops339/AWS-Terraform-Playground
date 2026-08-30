################################################################################
# Deployment matrix tests
#
# Exercises the launch-type and deployment-type derivation in locals.tf without
# touching AWS. Every provider call is mocked, so these run for free in CI.
#
#   terraform test
#
# command = plan is sufficient here because everything asserted on is derived
# from inputs rather than computed by AWS.
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_account_alias" {
    defaults = {
      account_alias = "testacct"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-00000000000000000"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  cluster_name  = "matrix"
  vpc_id        = "vpc-00000000000000000"
  load_balanced = false
  target_groups = []
}

################################################################################
# Fargate: the four ECS-native strategies plus the external controller
################################################################################

run "fargate_deployment_types" {
  command = plan

  variables {
    launch_type_default = "FARGATE"

    container_config = {
      rolling = {
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count            = 2
          deployment_configuration = { strategy = "ROLLING" }
        }
      }

      blue_green = {
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count            = 2
          deployment_configuration = { strategy = "BLUE_GREEN", bake_time_in_minutes = 10 }
        }
      }

      linear = {
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count = 2
          deployment_configuration = {
            strategy             = "LINEAR"
            linear_configuration = { step_percent = 20, step_bake_time_in_minutes = 3 }
          }
        }
      }

      canary = {
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count = 2
          deployment_configuration = {
            strategy             = "CANARY"
            canary_configuration = { canary_percent = 10, canary_bake_time_in_minutes = 15 }
          }
        }
      }

      external = {
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count         = 1
          deployment_controller = { type = "EXTERNAL" }
        }
      }
    }
  }

  # All five resolve to Fargate on awsvpc.
  assert {
    condition = alltrue([
      for k, v in output.service_deployment_summary : v.launch_type == "FARGATE" && v.network_mode == "awsvpc"
    ])
    error_message = "Every service should resolve to the FARGATE launch type on the awsvpc network mode."
  }

  assert {
    condition     = output.service_deployment_summary["rolling"].deployment_strategy == "ROLLING"
    error_message = "rolling should resolve to the ROLLING strategy."
  }

  assert {
    condition     = output.service_deployment_summary["blue_green"].deployment_strategy == "BLUE_GREEN"
    error_message = "blue_green should resolve to the BLUE_GREEN strategy."
  }

  assert {
    condition     = output.service_deployment_summary["linear"].deployment_strategy == "LINEAR"
    error_message = "linear should resolve to the LINEAR strategy."
  }

  assert {
    condition     = output.service_deployment_summary["canary"].deployment_strategy == "CANARY"
    error_message = "canary should resolve to the CANARY strategy."
  }

  # ROLLING updates in place; the other three shift traffic between target groups.
  assert {
    condition = (
      output.service_deployment_summary["rolling"].shifts_traffic == false &&
      output.service_deployment_summary["blue_green"].shifts_traffic &&
      output.service_deployment_summary["linear"].shifts_traffic &&
      output.service_deployment_summary["canary"].shifts_traffic
    )
    error_message = "Only the non-ROLLING ECS-native strategies should be marked as shifting traffic."
  }

  # The external controller ignores deployment_strategy entirely.
  assert {
    condition     = output.service_deployment_summary["external"].deployment_controller == "EXTERNAL"
    error_message = "external should use the EXTERNAL deployment controller."
  }

  # Each controller owns its own aws_ecs_service resource.
  assert {
    condition     = length(output.service_deployment_strategy) == 4
    error_message = "Only the four ECS-controller services should appear in service_deployment_strategy."
  }

  # Traffic shifting is done natively by ECS, so no CodeDeploy resources exist.
  assert {
    condition     = length(aws_ecs_service.main) == 4 && length(aws_ecs_service.external) == 1
    error_message = "Four ECS-controller services and one external service should be created."
  }
}

################################################################################
# EC2: network modes, DAEMON scheduling and capacity providers
################################################################################

run "ec2_deployment_types" {
  command = plan

  variables {
    launch_type_default = "EC2"
    capacity_providers  = []

    default_capacity_provider_strategy = []

    ec2_capacity_providers = {
      ondemand = {
        vpc_id     = "vpc-00000000000000000"
        subnet_ids = ["subnet-00000000000000000", "subnet-11111111111111111"]
        min_size   = 2
        max_size   = 10
      }
      spot = {
        vpc_id                  = "vpc-00000000000000000"
        subnet_ids              = ["subnet-00000000000000000"]
        instance_types_override = ["m6i.large", "m6a.large"]
        min_size                = 0
        max_size                = 20
      }
    }

    container_config = {
      # Default network mode for EC2 is bridge.
      bridge_service = {
        task_definition = { memory = 512, image = "nginx" }
        service         = { desired_count = 2 }
      }

      # awsvpc on EC2 behaves like Fargate: per-task ENI.
      awsvpc_service = {
        task_definition = { network_mode = "awsvpc", cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count   = 2
          subnets         = ["subnet-00000000000000000"]
          security_groups = ["sg-00000000000000000"]
        }
      }

      # DAEMON: one task per container instance, no desired_count.
      daemon_service = {
        task_definition = { network_mode = "host", memory = 256, image = "fluent-bit" }
        service         = { scheduling_strategy = "DAEMON" }
      }

      # A capacity provider strategy must suppress launch_type.
      spot_service = {
        task_definition = { memory = 512, image = "nginx" }
        service = {
          desired_count = 4
          capacity_provider_strategy = [
            { capacity_provider = "testacct-matrix-spot", weight = 1 },
          ]
        }
      }
    }
  }

  assert {
    condition     = output.service_deployment_summary["bridge_service"].network_mode == "bridge"
    error_message = "EC2 services should default to the bridge network mode."
  }

  assert {
    condition     = output.service_deployment_summary["awsvpc_service"].network_mode == "awsvpc"
    error_message = "An explicit awsvpc network mode should be honoured on EC2."
  }

  assert {
    condition     = output.service_deployment_summary["daemon_service"].scheduling_strategy == "DAEMON"
    error_message = "daemon_service should use the DAEMON scheduling strategy."
  }

  assert {
    condition = alltrue([
      for k, v in output.service_deployment_summary : v.launch_type == "EC2"
    ])
    error_message = "Every service should resolve to the EC2 launch type."
  }

  # launch_type and capacity_provider_strategy are mutually exclusive in the
  # ECS API, so naming a provider must leave the strategy list populated.
  assert {
    condition     = tolist(output.service_deployment_summary["spot_service"].capacity_providers) == tolist(["testacct-matrix-spot"])
    error_message = "spot_service should be placed through its capacity provider strategy."
  }

  assert {
    condition     = length(output.service_deployment_summary["bridge_service"].capacity_providers) == 0
    error_message = "bridge_service should use launch_type rather than a capacity provider strategy."
  }

  # Both capacity providers should be built and named consistently.
  assert {
    condition     = length(output.capacity_provider_names) == 2
    error_message = "Both EC2 capacity providers should be created."
  }
}

################################################################################
# Mixed capacity on one cluster
################################################################################

run "mixed_fargate_and_ec2" {
  command = plan

  variables {
    launch_type_default = "FARGATE"
    capacity_providers  = ["FARGATE", "FARGATE_SPOT"]

    ec2_capacity_providers = {
      gpu = {
        vpc_id     = "vpc-00000000000000000"
        subnet_ids = ["subnet-00000000000000000"]
        min_size   = 0
        max_size   = 4
      }
    }

    container_config = {
      api = {
        task_definition = { cpu = 512, memory = 1024, image = "nginx" }
        service         = { desired_count = 2, launch_type = "FARGATE" }
      }
      gpu_inference = {
        task_definition = { network_mode = "awsvpc", cpu = 4096, memory = 15000, image = "infer" }
        service = {
          launch_type     = "EC2"
          desired_count   = 1
          subnets         = ["subnet-00000000000000000"]
          security_groups = ["sg-00000000000000000"]
        }
      }
      node_agent = {
        task_definition = { network_mode = "host", memory = 256, image = "agent" }
        service         = { launch_type = "EC2", scheduling_strategy = "DAEMON" }
      }
    }
  }

  assert {
    condition     = output.service_deployment_summary["api"].launch_type == "FARGATE"
    error_message = "api should run on Fargate."
  }

  assert {
    condition = (
      output.service_deployment_summary["gpu_inference"].launch_type == "EC2" &&
      output.service_deployment_summary["node_agent"].launch_type == "EC2"
    )
    error_message = "gpu_inference and node_agent should run on EC2 in the same cluster as the Fargate api service."
  }

  # DAEMON is the one shape Fargate cannot express.
  assert {
    condition = (
      output.service_deployment_summary["node_agent"].scheduling_strategy == "DAEMON" &&
      output.service_deployment_summary["api"].scheduling_strategy == "REPLICA"
    )
    error_message = "Only the EC2 node_agent should use DAEMON scheduling."
  }
}

################################################################################
# Validation guardrails
################################################################################

run "existing_cluster_requires_arn" {
  command = plan

  variables {
    create_cluster = false
    container_config = {
      app = {
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service         = { desired_count = 1 }
      }
    }
  }

  expect_failures = [
    var.existing_cluster_arn,
  ]
}

################################################################################
# ECS infrastructure IAM role
#
# ECS-native traffic shifting needs no CodeDeploy, but it does need the role
# ECS assumes to reweight listener rules. advanced_configuration.role_arn is
# required by the provider, so the module must supply one.
################################################################################

run "infrastructure_role_created_only_when_needed" {
  command = plan

  variables {
    launch_type_default = "FARGATE"
    load_balanced       = true

    target_groups = [
      {
        target_group_arn           = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/blue/0000000000000000"
        alternate_target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/green/1111111111111111"
        production_listener_rule   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/lb/0/0/0"
        container_name             = "app"
        container_port             = 8080
      },
    ]

    container_config = {
      # ROLLING updates in place, so ECS never touches the load balancer.
      rolling = {
        container_name  = "app"
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count            = 2
          deployment_configuration = { strategy = "ROLLING" }
        }
      }

      # These three shift traffic and therefore need the role.
      blue_green = {
        container_name  = "app"
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count            = 2
          deployment_configuration = { strategy = "BLUE_GREEN" }
        }
      }

      canary = {
        container_name  = "app"
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count            = 2
          deployment_configuration = { strategy = "CANARY" }
        }
      }

      # Brings its own role, so the module must not create a second one.
      byo_role = {
        container_name  = "app"
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count = 2
          deployment_configuration = {
            strategy                 = "BLUE_GREEN"
            ecs_alb_service_role_arn = "arn:aws:iam::123456789012:role/my-own-ecs-infra-role"
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.infrastructure) == 2
    error_message = "Exactly the two traffic-shifting services without their own role should get one created."
  }

  assert {
    condition = (
      contains(keys(aws_iam_role.infrastructure), "blue_green") &&
      contains(keys(aws_iam_role.infrastructure), "canary")
    )
    error_message = "blue_green and canary should each get an infrastructure role."
  }

  assert {
    condition     = !contains(keys(aws_iam_role.infrastructure), "rolling")
    error_message = "A ROLLING service does not shift traffic and needs no infrastructure role."
  }

  assert {
    condition     = !contains(keys(aws_iam_role.infrastructure), "byo_role")
    error_message = "A service supplying ecs_alb_service_role_arn should not get a second role created."
  }

  # An explicitly supplied role must win over the created one.
  assert {
    condition     = output.infrastructure_iam_role_arns["byo_role"] == "arn:aws:iam::123456789012:role/my-own-ecs-infra-role"
    error_message = "An explicit ecs_alb_service_role_arn should take precedence."
  }

  assert {
    condition     = output.infrastructure_iam_role_arns["rolling"] == null
    error_message = "A ROLLING service should resolve to no infrastructure role."
  }

  # The load balancer policy is what actually permits the traffic shift.
  assert {
    condition     = length(aws_iam_role_policy_attachment.infrastructure_load_balancer) == 2
    error_message = "Both traffic-shifting services should get the load balancer policy attached."
  }
}

################################################################################
# CodeDeploy is not supported
#
# Blue/green, linear and canary are performed natively by ECS, so the module
# has no CodeDeploy application, deployment group, AppSpec or service role.
#
# A leftover CODE_DEPLOY controller must fail loudly: it would otherwise match
# neither the ECS nor the EXTERNAL service grouping, and the service would
# silently not be created at all.
################################################################################

run "codedeploy_controller_is_rejected" {
  command = plan

  variables {
    container_config = {
      legacy = {
        task_definition = { cpu = 256, memory = 512, image = "nginx" }
        service = {
          desired_count         = 2
          deployment_controller = { type = "CODE_DEPLOY" }
        }
      }
    }
  }

  expect_failures = [
    var.container_config,
  ]
}
