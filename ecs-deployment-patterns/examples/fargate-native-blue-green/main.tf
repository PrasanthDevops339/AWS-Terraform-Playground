################################################################################
# ECS-native blue/green - no CodeDeploy anywhere
#
# This is the self-contained version: it builds the load balancer, both target
# groups and both listener rules, so you can read the whole traffic-shifting
# path in one file. The other examples take those as inputs.
#
# The entire mechanism is:
#
#   1. Two target groups, blue and green. Terraform creates them but attaches
#      nothing - ECS registers and deregisters task IPs itself.
#   2. A production listener rule that weighted-forwards across both, starting
#      100/0.
#   3. A test listener rule pointing at green, for smoke tests before the cut.
#   4. deployment_configuration { strategy = "BLUE_GREEN" } on the service.
#   5. An IAM role ECS assumes to reweight rule 2. The module creates it.
#
# ECS then does the deployment: stands up a green task set, registers it in the
# green target group, bakes, reweights the production rule to 0/100, and tears
# down blue. Swap BLUE_GREEN for LINEAR or CANARY and only step 4 changes.
#
# No CodeDeploy application, no deployment group, no AppSpec, no service role.
################################################################################

provider "aws" {
  region = var.region
}

locals {
  name           = "${var.name_prefix}-bg"
  container_name = "app"
}

################################################################################
# Load balancer
################################################################################

resource "aws_security_group" "alb" {
  name_prefix = "${local.name}-alb-"
  description = "ALB for ${local.name}"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-alb" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_production" {
  security_group_id = aws_security_group.alb.id
  description       = "Production traffic"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.ingress_cidr
}

# The test listener is deliberately reachable from a narrower range: it serves
# the not-yet-promoted version.
resource "aws_vpc_security_group_ingress_rule" "alb_test" {
  security_group_id = aws_security_group.alb.id
  description       = "Pre-cutover smoke tests against the green task set"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = var.test_ingress_cidr
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id = aws_security_group.alb.id
  description       = "To the ECS tasks"
  ip_protocol       = "tcp"
  from_port         = var.container_port
  to_port           = var.container_port
  cidr_ipv4         = var.vpc_cidr_block
}

resource "aws_lb" "this" {
  name               = local.name
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true

  tags = { Name = local.name }
}

################################################################################
# Target groups - blue and green
#
# ECS registers task IPs into these itself, which is why there is no
# aws_lb_target_group_attachment here. Adding one would fight ECS.
################################################################################

resource "aws_lb_target_group" "blue" {
  name        = "${local.name}-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # awsvpc / Fargate registers by IP, never by instance

  deregistration_delay = 5

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.name}-blue", Role = "blue" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "green" {
  name        = "${local.name}-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 5

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.name}-green", Role = "green" }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Listeners
################################################################################

resource "aws_lb_listener" "production" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # Traffic is routed by the rule below, not by the default action.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: no route"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.this.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: no route"
      status_code  = "404"
    }
  }
}

################################################################################
# Listener rules - the thing ECS actually manipulates
################################################################################

# This is the rule whose weights ECS rewrites to shift traffic. It must be a
# weighted forward across BOTH target groups, even though green starts at 0.
resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.production.arn
  priority     = 1

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  # ECS owns these weights after the first deployment.
  #
  # A completed blue/green deployment leaves green at 100 and blue at 0, and
  # the two swap roles again on the next release. Without this, every plan
  # after a deployment would show drift and try to shove traffic back onto the
  # target group that is no longer live. Note the upstream
  # terraform-aws-modules ALB module does not do this for you.
  lifecycle {
    ignore_changes = [action]
  }
}

# Lets you exercise the new version before it takes production traffic.
resource "aws_lb_listener_rule" "test" {
  listener_arn = aws_lb_listener.test.arn
  priority     = 1

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = 100
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

################################################################################
# Task security group
################################################################################

resource "aws_security_group" "tasks" {
  name_prefix = "${local.name}-tasks-"
  description = "ECS tasks for ${local.name}"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-tasks" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "From the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "tasks_https" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS for image pulls, secrets and telemetry"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

################################################################################
# The ECS service
#
# Everything above is load balancer plumbing. This is the only part that
# selects the deployment strategy.
################################################################################

module "ecs" {
  source = "../../../Terrafrom-AWS-Prasanth/terraform-aws-ecs"

  cluster_name = var.name_prefix
  vpc_id       = var.vpc_id
  tags         = var.tags

  container_config = {
    app = {
      container_name = local.container_name

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.container_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.task_role_arn
        task_log_group_name = "/ecs/${var.name_prefix}/app"

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
        launch_type   = "FARGATE"
        desired_count = 2

        subnets         = var.private_subnet_ids
        security_groups = [aws_security_group.tasks.id]

        enable_execute_command            = true
        health_check_grace_period_seconds = 60

        # ---- The whole deployment strategy, in five lines ----
        deployment_configuration = {
          strategy = "BLUE_GREEN"

          # Soak time on green before blue is torn down. This is the window in
          # which an alarm can still trigger an automatic rollback.
          bake_time_in_minutes = 5

          # No ecs_alb_service_role_arn here on purpose. The module creates the
          # ECS infrastructure role and wires it in, because the provider
          # requires advanced_configuration.role_arn and there is nothing
          # useful for you to decide about it.
        }

        target_groups = [
          {
            target_group_arn = aws_lb_target_group.blue.arn
            container_name   = local.container_name
            container_port   = var.container_port

            # The three inputs that turn a rolling service into a
            # traffic-shifting one.
            alternate_target_group_arn = aws_lb_target_group.green.arn
            production_listener_rule   = aws_lb_listener_rule.production.arn
            test_listener_rule         = aws_lb_listener_rule.test.arn
          },
        ]
      }

      alarms = {
        enabled        = true
        sns_topic_arns = var.alarm_sns_topic_arns
      }
    }
  }
}
