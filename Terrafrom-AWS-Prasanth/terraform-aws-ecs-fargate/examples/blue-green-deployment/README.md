# Blue/Green Deployment with CodeDeploy Example

This example demonstrates ECS services using CodeDeploy for blue/green deployments.

## Configuration

```hcl
module "ecs_fargate_blue_green" {
  source = "../.."

  cluster_name = "blue-green-cluster"
  vpc_id       = "vpc-12345678"

  container_config = {
    web_app = {
      container_name = "web-application"
      task_definition = {
        cpu                = 512
        memory            = 1024
        image             = "webapp:v1.0"
        container_port    = 80
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/webapp"
      }
      service = {
        desired_count    = 3
        security_groups  = [aws_security_group.webapp.id]
        subnets         = data.aws_subnets.private.ids
        
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
    }
  }

  # Load balancer configuration
  load_balanced = true
  target_groups = [
    {
      target_group_arn = aws_lb_target_group.blue.arn
      container_name   = "web-application"
      container_port   = 80
    },
    {
      target_group_arn = aws_lb_target_group.green.arn
      container_name   = "web-application" 
      container_port   = 80
    }
  ]

  tags = {
    Environment    = "production"
    DeploymentType = "blue-green"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "webapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = data.aws_subnets.public.ids

  enable_deletion_protection = false

  tags = {
    Name = "webapp-alb"
  }
}

# Blue Target Group
resource "aws_lb_target_group" "blue" {
  name        = "webapp-blue-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "webapp-blue-tg"
  }
}

# Green Target Group  
resource "aws_lb_target_group" "green" {
  name        = "webapp-green-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "webapp-green-tg"
  }
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
}

# CodeDeploy Service Role
resource "aws_iam_role" "codedeploy_service" {
  name = "codedeploy-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_service" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
  role       = aws_iam_role.codedeploy_service.name
}

# CloudWatch Alarms for Deployment Monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "webapp-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  
  dimensions = {
    ServiceName = module.ecs_fargate_blue_green.service_name["web_app"]
    ClusterName = module.ecs_fargate_blue_green.cluster_name
  }
}
```

## Deployment Process

1. **Initial State**: Service runs with blue target group receiving traffic
2. **Deployment**: CodeDeploy creates new task definition revision
3. **Green Deployment**: New tasks are deployed to green target group
4. **Health Checks**: Green environment is validated
5. **Traffic Switch**: Load balancer switches traffic to green target group
6. **Blue Termination**: Original blue tasks are terminated after wait period

## Benefits

- **Zero Downtime**: Traffic switches atomically between environments
- **Quick Rollback**: Instant rollback capability if issues are detected
- **Automated Testing**: Integration with health checks and alarms
- **Risk Mitigation**: Blue environment remains available during deployment

## Prerequisites

- Application Load Balancer with two target groups
- CodeDeploy service role with appropriate permissions
- CloudWatch alarms for monitoring (optional but recommended)
- ECS task and execution roles