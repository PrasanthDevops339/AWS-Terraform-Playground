# Service Connect with TLS - Complete Example
# This example demonstrates ECS service connect with TLS encryption

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

# AWS Private Certificate Authority
resource "aws_acmpca_certificate_authority" "service_connect_ca" {
  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name                  = var.ca_common_name
      country                     = var.ca_country
      locality                    = var.ca_locality
      organization                = var.ca_organization
      organizational_unit         = var.ca_organizational_unit
      state                       = var.ca_state
    }
  }

  permanent_deletion_time_in_days = var.ca_deletion_days
  type                           = "ROOT"

  tags = merge(var.tags, {
    Name = "${var.project_name}-service-connect-ca"
  })
}

# Certificate for the CA
resource "aws_acmpca_certificate" "ca_certificate" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.service_connect_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.service_connect_ca.certificate_signing_request
  signing_algorithm          = "SHA512WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

# Install the certificate in the CA
resource "aws_acmpca_certificate_authority_certificate" "ca_certificate" {
  certificate_authority_arn = aws_acmpca_certificate_authority.service_connect_ca.arn
  certificate               = aws_acmpca_certificate.ca_certificate.certificate
  certificate_chain         = aws_acmpca_certificate.ca_certificate.certificate_chain
}

# KMS Key for Service Connect TLS
resource "aws_kms_key" "service_connect_tls" {
  description             = "KMS key for ECS Service Connect TLS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow ECS Service Connect"
        Effect = "Allow"
        Principal = {
          Service = "ecs.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-service-connect-tls-key"
  })
}

resource "aws_kms_alias" "service_connect_tls" {
  name          = "alias/${var.project_name}-service-connect-tls"
  target_key_id = aws_kms_key.service_connect_tls.key_id
}

# Cloud Map Namespace
resource "aws_service_discovery_private_dns_namespace" "service_connect" {
  name        = var.service_connect_namespace
  vpc         = var.vpc_id
  description = "Service Connect namespace for ${var.project_name}"

  tags = var.tags
}

# ECS Fargate Module with Service Connect TLS
module "ecs_fargate_service_connect_tls" {
  source = "../.."

  cluster_name = "${var.project_name}-cluster"
  vpc_id       = var.vpc_id

  # Enable Service Connect with TLS
  service_connect_configuration = {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.service_connect.arn
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group  = aws_cloudwatch_log_group.service_connect.name
        awslogs-region = data.aws_region.current.name
        awslogs-stream-prefix = "service-connect"
      }
    }
  }

  container_config = {
    # Secure API Service with TLS
    secure_api = {
      container_name = "secure-api"
      task_definition = {
        cpu                = var.api_cpu
        memory            = var.api_memory
        image             = var.api_image
        container_port    = var.api_port
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = aws_cloudwatch_log_group.secure_api.name
        
        envvars = [
          {
            name  = "APP_ENV"
            value = var.environment
          },
          {
            name  = "API_VERSION"
            value = var.api_version
          },
          {
            name  = "TLS_ENABLED"
            value = "true"
          }
        ]
      }
      service = {
        desired_count    = var.api_desired_count
        security_groups  = [aws_security_group.secure_api.id]
        subnets         = data.aws_subnets.private.ids
        assign_public_ip = false
        
        # Service Connect with TLS
        service_connect = {
          enabled   = true
          services = [{
            port_name = "secure-api-port"
            discovery_name = "secure-api"
            ingress_port_override = var.api_port
            client_aliases = [{
              port     = var.api_port
              dns_name = "secure-api.${var.service_connect_namespace}"
            }]
            # TLS Configuration
            tls = {
              issuer_certificate_authority = {
                aws_pca_authority_arn = aws_acmpca_certificate_authority.service_connect_ca.arn
              }
              kms_key  = aws_kms_key.service_connect_tls.arn
              role_arn = aws_iam_role.service_connect_tls.arn
            }
            timeout = {
              idle_timeout_seconds        = var.tls_idle_timeout
              per_request_timeout_seconds = var.tls_request_timeout
            }
          }]
        }
      }
      
      # Auto Scaling
      autoscaling = {
        max_capacity = var.api_max_capacity
        min_capacity = var.api_min_capacity
        cpu_scaling_policy_configuration = {
          target_value = 70
        }
        memory_scaling_policy_configuration = {
          target_value = 80
        }
      }
    }

    # Client Service connecting to secure API
    client_service = {
      container_name = "client-app"
      task_definition = {
        cpu                = var.client_cpu
        memory            = var.client_memory
        image             = var.client_image
        container_port    = var.client_port
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = aws_cloudwatch_log_group.client_service.name
        
        envvars = [
          {
            name  = "APP_ENV"
            value = var.environment
          },
          {
            name  = "API_ENDPOINT"
            value = "https://secure-api.${var.service_connect_namespace}:${var.api_port}"
          },
          {
            name  = "CLIENT_VERSION"
            value = var.client_version
          }
        ]
      }
      service = {
        desired_count    = var.client_desired_count
        security_groups  = [aws_security_group.client.id]
        subnets         = data.aws_subnets.private.ids
        assign_public_ip = false
        
        # Service Connect (client only)
        service_connect = {
          enabled = true
          services = [{
            port_name = "client-port"
            discovery_name = "client-app"
            client_aliases = [{
              port     = var.client_port
              dns_name = "client-app.${var.service_connect_namespace}"
            }]
          }]
        }
      }
      
      # Auto Scaling
      autoscaling = {
        max_capacity = var.client_max_capacity
        min_capacity = var.client_min_capacity
        cpu_scaling_policy_configuration = {
          target_value = 60
        }
      }
    }

    # Database Service (PostgreSQL)
    database = {
      container_name = "postgres-db"
      task_definition = {
        cpu                = var.db_cpu
        memory            = var.db_memory
        image             = var.db_image
        container_port    = var.db_port
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = aws_cloudwatch_log_group.database.name
        
        envvars = [
          {
            name  = "POSTGRES_DB"
            value = var.db_name
          },
          {
            name  = "POSTGRES_USER"
            value = var.db_user
          }
        ]
        secrets = [
          {
            name      = "POSTGRES_PASSWORD"
            valueFrom = aws_ssm_parameter.db_password.arn
          }
        ]
      }
      service = {
        desired_count    = 1  # Database should have only 1 instance
        security_groups  = [aws_security_group.database.id]
        subnets         = data.aws_subnets.private.ids
        assign_public_ip = false
        
        # Service Connect with TLS for database
        service_connect = {
          enabled   = true
          services = [{
            port_name = "db-port"
            discovery_name = "postgres-db"
            client_aliases = [{
              port     = var.db_port
              dns_name = "postgres-db.${var.service_connect_namespace}"
            }]
            # TLS Configuration for database
            tls = {
              issuer_certificate_authority = {
                aws_pca_authority_arn = aws_acmpca_certificate_authority.service_connect_ca.arn
              }
              kms_key  = aws_kms_key.service_connect_tls.arn
              role_arn = aws_iam_role.service_connect_tls.arn
            }
          }]
        }
      }
    }
  }

  tags = var.tags
}

# SSM Parameter for Database Password
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/database/password"
  type  = "SecureString"
  value = var.db_password

  tags = var.tags
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "service_connect" {
  name              = "/aws/ecs/service-connect"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "secure_api" {
  name              = "/aws/ecs/secure-api"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "client_service" {
  name              = "/aws/ecs/client-service"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "database" {
  name              = "/aws/ecs/database"
  retention_in_days = var.log_retention_days

  tags = var.tags
}