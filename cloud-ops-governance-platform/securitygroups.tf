module "lambda_database_access_security_group" {
  source      = "tfe.prasanth.com/prasanth/security-group/aws"
  sg_name     = "sg_lambda_database_security_group"
  description = "Used for lambda function access to the aurora mysql database"
  vpc_id      = data.aws_ssm_parameter.vpc_use2.value

  ingress_rules = [
    {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "198.51.100.0/24"
      description = "Allow ingress port 80"
    }
  ]

  egress_rules = [
    {
      from_port   = 3306
      to_port     = 3306
      ip_protocol = "tcp"
      cidr_ipv4   = "192.0.2.0/24"
      description = "Allow database access"
    },
    {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "198.51.100.0/24"
      description = "Allow egress to port 443"
    },
    {
      from_port      = 443
      to_port        = 443
      ip_protocol    = "tcp"
      # prefix list for S3 endpoint (dummy)
      prefix_list_id = "pl-0123456789abcdef0"
      description    = "Allow egress to S3"
    },
    {
      from_port      = 443
      to_port        = 443
      ip_protocol    = "tcp"
      # prefix list for Dynamo endpoint (dummy)
      prefix_list_id = "pl-0fedcba9876543210"
      description    = "Allow egress to DynamoDB"
    },
    {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "203.0.113.0/24"
      description = "Allow egress to SNOW"
    }
  ]
}

# Security group for CCOPS Aurora DB
module "security-group" {
  source  = "tfe.prasanth.com/prasanth/security-group/aws"
  version = "1.0.2"

  create_sg   = true
  sg_name     = "aurora-mysql-cluster-security-group"
  description = "security group for data base instance"
  vpc_id      = data.aws_vpc.vpc_id.id

  ############ Inress rules ############
  ingress_rules = [
    {
      from_port   = 3306
      to_port     = 3306
      ip_protocol = "TCP"
      cidr_ipv4   = "198.51.100.0/24"
      description = "From allowed CIDRs"
    }
  ]
}

resource "aws_security_group" "security_group" {
  name   = "prasanth-operations-dev-ccop-ecs-security-group"
  vpc_id = data.aws_ssm_parameter.vpc_use2.value

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"]
    description = "any"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.0.113.0/24"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"]
  }
}
