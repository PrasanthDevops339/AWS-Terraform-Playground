########################################
# examples/complete/lb.tf
#
# Two load balancers:
#   alb_public   — internet-facing, port 80 → frontend (ROLLING, single TG)
#   alb_internal — internal, port 8080 → api (CANARY, blue + green TGs)
########################################

locals {
  account_alias = data.aws_iam_account_alias.current.account_alias
}

########################################
# Public ALB — frontend tier
########################################

module "alb_public" {
  source = "tfe.com/elb/aws"

  name                    = "${local.account_alias}-${var.environment}-frontend"
  load_balancer_type      = "application"
  internal                = false
  vpc_id                  = data.aws_vpc.main.id
  subnets                 = data.aws_subnets.public.ids
  security_groups         = [module.sg_lb_public.security_group_id]
  enable_deletion_protection = false

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      default_action = {
        type             = "forward"
        target_group_key = "frontend-blue"
      }
    }
  }

  target_groups = {
    "frontend-blue" = {
      name        = "${local.account_alias}-${var.environment}-fe-blue"
      target_type = "ip"
      port        = 80
      protocol    = "HTTP"
      vpc_id      = data.aws_vpc.main.id

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/health"
        port                = "80"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 10
        protocol            = "HTTP"
        matcher             = "200-299"
      }
    }
  }

  tags = var.tags
}

########################################
# Internal ALB — api tier (blue + green for CANARY)
########################################

module "alb_internal" {
  source = "tfe.com/elb/aws"

  name                    = "${local.account_alias}-${var.environment}-api"
  load_balancer_type      = "application"
  internal                = true
  vpc_id                  = data.aws_vpc.main.id
  subnets                 = data.aws_subnets.private.ids
  security_groups         = [module.sg_lb_internal.security_group_id]
  enable_deletion_protection = false

  listeners = {
    "api-http" = {
      port     = 8080
      protocol = "HTTP"
      default_action = {
        type             = "forward"
        target_group_key = "api-blue"
      }
    }
  }

  # Two target groups — ECS CANARY shifts traffic from blue to green
  target_groups = {
    "api-blue" = {
      name        = "${local.account_alias}-${var.environment}-api-blue"
      target_type = "ip"
      port        = 8080
      protocol    = "HTTP"
      vpc_id      = data.aws_vpc.main.id

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/health"
        port                = "8080"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 10
        protocol            = "HTTP"
        matcher             = "200-299"
      }
    }

    "api-green" = {
      name        = "${local.account_alias}-${var.environment}-api-green"
      target_type = "ip"
      port        = 8080
      protocol    = "HTTP"
      vpc_id      = data.aws_vpc.main.id

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/health"
        port                = "8080"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 10
        protocol            = "HTTP"
        matcher             = "200-299"
      }
    }
  }

  tags = var.tags
}
