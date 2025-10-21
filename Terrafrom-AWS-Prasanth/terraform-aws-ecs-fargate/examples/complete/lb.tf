#########################
# examples/complete/lb.tf
#########################

locals {
  account_alias = data.aws_iam_account_alias.current.account_alias
}

module "alb" {
  source                  = "tfe.com/elb/aws"
  name                    = "ecs-complete"
  load_balancer_type      = "application"
  vpc_id                  = data.aws_vpc.main.id
  subnets                 = data.aws_subnets.app_subnets.ids
  enable_deletion_protection = false
  security_groups         = [module.lb_sg.security_group_id]

  listeners = {
    ex-forward = {
      port     = 80
      protocol = "HTTP"
    }
    forward = {
      target_group_key = "ex-ip"
    }
  }
  target_groups = {
    ex-ip = {
      name        = "${local.account_alias}-ecs-test"
      target_type = "ip"
      port        = 80
      protocol    = "HTTP"
      vpc_id      = data.aws_vpc.main.id

      health_check = {
        enabled            = true
        interval           = 45
        path               = "/"
        port               = "80"
        healthy_threshold  = 3
        unhealthy_threshold= 3
        timeout            = 30
        protocol           = "HTTP"
      }
    }
  }
}
