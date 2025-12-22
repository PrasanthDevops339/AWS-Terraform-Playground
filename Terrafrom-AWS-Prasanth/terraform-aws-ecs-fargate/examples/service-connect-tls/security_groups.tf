# Security Groups for Service Connect with TLS Example

# Security Group for Secure API Service
resource "aws_security_group" "secure_api" {
  name        = "${var.project_name}-secure-api-sg"
  description = "Security group for secure API service"
  vpc_id      = var.vpc_id

  ingress {
    description = "API Port from Client Services"
    from_port   = var.api_port
    to_port     = var.api_port
    protocol    = "tcp"
    security_groups = [
      aws_security_group.client.id
    ]
  }

  ingress {
    description = "HTTPS API Port from Client Services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      aws_security_group.client.id
    ]
  }

  # Allow Service Connect proxy communication
  ingress {
    description = "Service Connect Proxy"
    from_port   = 15000
    to_port     = 15010
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Database Connection"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    security_groups = [
      aws_security_group.database.id
    ]
  }

  egress {
    description = "HTTPS Outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Service Connect proxy communication
  egress {
    description = "Service Connect Proxy"
    from_port   = 15000
    to_port     = 15010
    protocol    = "tcp"
    self        = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-secure-api-sg"
  })
}

# Security Group for Client Service
resource "aws_security_group" "client" {
  name        = "${var.project_name}-client-sg"
  description = "Security group for client service"
  vpc_id      = var.vpc_id

  ingress {
    description = "Client Port"
    from_port   = var.client_port
    to_port     = var.client_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # Allow Service Connect proxy communication
  ingress {
    description = "Service Connect Proxy"
    from_port   = 15000
    to_port     = 15010
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "API Connection"
    from_port   = var.api_port
    to_port     = var.api_port
    protocol    = "tcp"
    security_groups = [
      aws_security_group.secure_api.id
    ]
  }

  egress {
    description = "HTTPS API Connection"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      aws_security_group.secure_api.id
    ]
  }

  egress {
    description = "HTTPS Outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Service Connect proxy communication
  egress {
    description = "Service Connect Proxy"
    from_port   = 15000
    to_port     = 15010
    protocol    = "tcp"
    self        = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-client-sg"
  })
}

# Security Group for Database Service
resource "aws_security_group" "database" {
  name        = "${var.project_name}-database-sg"
  description = "Security group for database service"
  vpc_id      = var.vpc_id

  ingress {
    description = "Database Port from API Services"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    security_groups = [
      aws_security_group.secure_api.id
    ]
  }

  # Allow Service Connect proxy communication
  ingress {
    description = "Service Connect Proxy"
    from_port   = 15000
    to_port     = 15010
    protocol    = "tcp"
    self        = true
  }

  # Minimal egress for updates and logging
  egress {
    description = "HTTPS Outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Service Connect proxy communication
  egress {
    description = "Service Connect Proxy"
    from_port   = 15000
    to_port     = 15010
    protocol    = "tcp"
    self        = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-database-sg"
  })
}