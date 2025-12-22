# Blue/Green Deployment with CodeDeploy - Complete Example
# This example demonstrates ECS services using CodeDeploy for blue/green deployments

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get VPC data
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Get subnet data
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = data.aws_subnets.public.ids

  enable_deletion_protection = false

  tags = var.tags
}

# Blue Target Group
resource "aws_lb_target_group" "blue" {
  name        = "${var.project_name}-blue-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-blue-tg"
  })
}

# Green Target Group  
resource "aws_lb_target_group" "green" {
  name        = "${var.project_name}-green-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-green-tg"
  })
}

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  tags = var.tags
}

# ALB Listener for test traffic (port 8080)
resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.main.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  tags = var.tags
}

# ECS Fargate Module with Blue/Green Deployment
module "ecs_fargate_blue_green" {
  source = "../.."

  cluster_name = "${var.project_name}-cluster"
  vpc_id       = var.vpc_id

  container_config = {
    web_app = {
      container_name = "web-application"
      task_definition = {
        cpu                = 512
        memory            = 1024
        image             = var.container_image
        container_port    = 80
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/webapp"
        
        # Environment variables
        envvars = [
          {
            name  = "APP_ENV"
            value = var.environment
          },
          {
            name  = "VERSION"
            value = var.app_version
          }
        ]
      }
      service = {
        desired_count    = var.desired_count
        security_groups  = [aws_security_group.webapp.id]
        subnets         = data.aws_subnets.private.ids
        assign_public_ip = false
        
        # Blue/Green Deployment Controller
        deployment_controller = {
          type = "CODE_DEPLOY"
        }
        
        # CodeDeploy Role ARN
        codedeploy_role_arn = aws_iam_role.codedeploy_service.arn
        
        # Auto Rollback Configuration
        auto_rollback_configuration = {
          enabled = true
          events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
        }
        
        # Blue/Green Deployment Configuration
        blue_green_deployment_config = {
          terminate_blue_instances_on_deployment_success = {
            action                         = "TERMINATE"
            termination_wait_time_in_minutes = 5
          }
          deployment_ready_option = {
            action_on_timeout    = "CONTINUE_DEPLOYMENT"
            wait_time_in_minutes = 0
          }
          green_fleet_provisioning_option = {
            action = "COPY_AUTO_SCALING_GROUP"
          }
        }
        
        # Deployment Style
        deployment_style = {
          deployment_option = "WITH_TRAFFIC_CONTROL"
          deployment_type   = "BLUE_GREEN"
        }
      }
      
      # Auto Scaling Configuration
      autoscaling = {
        max_capacity = var.max_capacity
        min_capacity = var.min_capacity
        create_cpu_scaling_policy = true
        create_memory_scaling_policy = true
        cpu_scaling_policy_configuration = {
          target_value = 70
          scale_in_cooldown = 300
          scale_out_cooldown = 300
        }
        memory_scaling_policy_configuration = {
          target_value = 80
          scale_in_cooldown = 300
          scale_out_cooldown = 300
        }
      }
    }
  }

  # Load balancer configuration
  load_balanced = true
  target_groups = [
    {
      target_group_arn = aws_lb_target_group.blue.arn
      container_name   = "web-application"
      container_port   = 80
    }
  ]

  tags = var.tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "webapp" {
  name              = "/aws/ecs/webapp"
  retention_in_days = 14

  tags = var.tags
}

# CloudWatch Alarms for Deployment Monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    ServiceName = "${data.aws_iam_account_alias.current.account_alias}-web_app"
    ClusterName = module.ecs_fargate_blue_green.cluster_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${var.project_name}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "This metric monitors ECS Memory utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    ServiceName = "${data.aws_iam_account_alias.current.account_alias}-web_app"
    ClusterName = module.ecs_fargate_blue_green.cluster_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "target_group_unhealthy" {
  alarm_name          = "${var.project_name}-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy targets in the load balancer"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    TargetGroup  = aws_lb_target_group.blue.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = var.tags
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = var.tags
}

# Get account alias
data "aws_iam_account_alias" "current" {}