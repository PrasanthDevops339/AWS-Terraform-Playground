########################################
# examples/complete/security_group.tf
#
# Per-tier security groups:
#   sg_lb_public   — internet-facing ALB (ingress 80/443 from 0.0.0.0/0)
#   sg_lb_internal — internal ALB (ingress 8080 from VPC CIDR)
#   sg_frontend    — frontend tasks (ingress 80 from public LB only)
#   sg_api         — api tasks (ingress 8080 from internal LB + frontend)
#   sg_worker      — worker tasks (egress only — pulls from SQS)
#   sg_efs         — EFS mount targets (ingress 2049 from api tasks only)
########################################

# ── Public LB ────────────────────────────────────────────────────────────────

module "sg_lb_public" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "${var.environment}-lb-public-sg"
  description = "Public ALB — accepts HTTP/HTTPS from internet"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from internet"
    },
    {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTPS from internet"
    }
  ]

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound"
  }]

  tags = var.tags
}

# ── Internal LB ──────────────────────────────────────────────────────────────

module "sg_lb_internal" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "${var.environment}-lb-internal-sg"
  description = "Internal ALB — accepts 8080 from within VPC"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      cidr_ipv4   = data.aws_vpc.main.cidr_block
      description = "API traffic from VPC"
    }
  ]

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound"
  }]

  tags = var.tags
}

# ── Frontend tasks ────────────────────────────────────────────────────────────

module "sg_frontend" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "${var.environment}-frontend-sg"
  description = "Frontend ECS tasks — ingress from public ALB only"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.sg_lb_public.security_group_id
      description                  = "Port 80 from public ALB"
    }
  ]

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound"
  }]

  tags = var.tags
}

# ── API tasks ─────────────────────────────────────────────────────────────────

module "sg_api" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "${var.environment}-api-sg"
  description = "API ECS tasks — ingress from internal ALB and frontend tasks"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.sg_lb_internal.security_group_id
      description                  = "Port 8080 from internal ALB"
    },
    {
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.sg_frontend.security_group_id
      description                  = "Port 8080 from frontend tasks (Service Connect)"
    }
  ]

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound"
  }]

  tags = var.tags
}

# ── Worker tasks ──────────────────────────────────────────────────────────────

module "sg_worker" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "${var.environment}-worker-sg"
  description = "Worker ECS tasks — no inbound, polls SQS outbound"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = []

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound (SQS, S3, ECR, etc.)"
  }]

  tags = var.tags
}

# ── EFS mount targets ─────────────────────────────────────────────────────────

module "sg_efs" {
  source      = "tfe.com/security-group/aws"
  sg_name     = "${var.environment}-efs-sg"
  description = "EFS mount targets — NFS ingress from api tasks only"
  vpc_id      = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port                    = 2049
      to_port                      = 2049
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.sg_api.security_group_id
      description                  = "NFS from api tasks"
    }
  ]

  egress_rules = [{
    ip_protocol = "-1"
    cidr_ipv4   = "0.0.0.0/0"
    description = "Allow all outbound"
  }]

  tags = var.tags
}
