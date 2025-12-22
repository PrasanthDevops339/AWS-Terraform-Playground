# Service Connect with TLS Example

This example demonstrates ECS service connect with TLS encryption.

## Configuration

```hcl
module "ecs_fargate_service_connect_tls" {
  source = "../.."

  cluster_name = "secure-cluster"
  vpc_id       = "vpc-12345678"

  # Enable Service Connect with TLS
  service_connect_configuration = {
    enabled   = true
    namespace = "secure-namespace"
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group  = "/aws/ecs/service-connect-tls"
        awslogs-region = "us-west-2"
      }
    }
  }

  container_config = {
    # Secure API Service with TLS
    secure_api = {
      container_name = "secure-api"
      task_definition = {
        cpu                = 512
        memory            = 1024
        image             = "api:latest"
        container_port    = 8443
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/secure-api"
      }
      service = {
        desired_count    = 2
        security_groups  = [aws_security_group.secure_api.id]
        subnets         = data.aws_subnets.private.ids
        
        # Service Connect with TLS
        service_connect = {
          enabled   = true
          services = [{
            port_name = "secure-api-port"
            client_aliases = [{
              port     = 8443
              dns_name = "secure-api.local"
            }]
            # TLS Configuration
            tls = {
              issuer_certificate_authority = {
                aws_pca_authority_arn = aws_acmpca_certificate_authority.example.arn
              }
              kms_key  = aws_kms_key.service_connect.arn
              role_arn = aws_iam_role.service_connect_tls.arn
            }
            timeout = {
              idle_timeout_seconds        = 60
              per_request_timeout_seconds = 30
            }
          }]
        }
      }
    }

    # Client Service connecting to secure API
    client_service = {
      container_name = "client-app"
      task_definition = {
        cpu                = 256
        memory            = 512
        image             = "client:latest"
        container_port    = 80
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/client"
        envvars = [
          {
            name  = "API_ENDPOINT"
            value = "https://secure-api.local:8443"
          }
        ]
      }
      service = {
        desired_count    = 1
        security_groups  = [aws_security_group.client.id]
        subnets         = data.aws_subnets.private.ids
        
        # Service Connect (client only)
        service_connect = {
          enabled = true
        }
      }
    }
  }

  tags = {
    Environment = "production"
    Security    = "tls-enabled"
  }
}

# AWS Private Certificate Authority
resource "aws_acmpca_certificate_authority" "example" {
  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = "example.com"
    }
  }

  permanent_deletion_time_in_days = 7
  type                           = "ROOT"

  tags = {
    Name = "Service Connect CA"
  }
}

# KMS Key for Service Connect TLS
resource "aws_kms_key" "service_connect" {
  description             = "KMS key for ECS Service Connect TLS"
  deletion_window_in_days = 7

  tags = {
    Name = "Service Connect TLS Key"
  }
}

# IAM Role for Service Connect TLS
resource "aws_iam_role" "service_connect_tls" {
  name = "service-connect-tls-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Service Connect TLS Role"
  }
}

# IAM Policy for Service Connect TLS
resource "aws_iam_role_policy" "service_connect_tls" {
  name = "service-connect-tls-policy"
  role = aws_iam_role.service_connect_tls.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm-pca:GetCertificate",
          "acm-pca:DescribeCertificateAuthority"
        ]
        Resource = aws_acmpca_certificate_authority.example.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.service_connect.arn
      }
    ]
  })
}
```

## TLS Benefits

- **End-to-end encryption**: All service-to-service communication is encrypted
- **Certificate management**: Automated certificate provisioning using AWS Private CA
- **Performance**: TLS termination handled by AWS infrastructure
- **Compliance**: Meets security requirements for encrypted internal communication

## Requirements

- AWS Private Certificate Authority (PCA)
- KMS key for encryption
- IAM roles with appropriate permissions
- Network security groups allowing HTTPS traffic