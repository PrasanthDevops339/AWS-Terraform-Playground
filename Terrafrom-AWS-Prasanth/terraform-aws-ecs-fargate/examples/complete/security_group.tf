###############################
# examples/complete/security_group.tf
###############################

# LB security group
module "lb_sg" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "ecs-lb-sg-complete"
  description = "Security group load balancer"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [{
    from_port   = 80
    to_port     = 80
    ip_protocol = "tcp"
    cidr_ipv4   = data.aws_vpc.main.cidr_block
    description = "Allow 80 from the specified CIDR"
  }]

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound on all ports"
  }]
}

# ECS service/task security group
module "ecs_sg" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "ecs-sg-complete"
  description = "Security group for ECS service"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = data.aws_vpc.main.cidr_block
      description = "Allow 80 from the specified CIDR"
    },
    {
      from_port                  = 80
      to_port                    = 80
      ip_protocol                = "tcp"
      referenced_security_group_id = module.lb_sg.security_group_id
      description                = "Allow 80 from load balancer"
    }
  ]

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound on all ports"
  }]
}
