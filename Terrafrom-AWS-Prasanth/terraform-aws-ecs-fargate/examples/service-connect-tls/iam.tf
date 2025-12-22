# IAM Roles for Service Connect with TLS Example

# ECS Task Execution Role
resource "aws_iam_role" "execution_role" {
  name = "${var.project_name}-execution-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.execution_role.name
}

# Additional policy for CloudWatch Logs and SSM
resource "aws_iam_role_policy" "execution_role_additional" {
  name = "${var.project_name}-execution-additional-policy"
  role = aws_iam_role.execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/*:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          aws_kms_key.service_connect_tls.arn
        ]
      }
    ]
  })
}

# ECS Task Role
resource "aws_iam_role" "task_role" {
  name = "${var.project_name}-task-role"

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

  tags = var.tags
}

# Policy for ECS Exec and Service Connect
resource "aws_iam_role_policy" "task_role_policy" {
  name = "${var.project_name}-task-policy"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "servicediscovery:DiscoverInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for Service Connect TLS
resource "aws_iam_role" "service_connect_tls" {
  name = "${var.project_name}-service-connect-tls-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-service-connect-tls-role"
  })
}

# IAM Policy for Service Connect TLS
resource "aws_iam_role_policy" "service_connect_tls" {
  name = "${var.project_name}-service-connect-tls-policy"
  role = aws_iam_role.service_connect_tls.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm-pca:GetCertificate",
          "acm-pca:DescribeCertificateAuthority",
          "acm-pca:GetCertificateAuthorityCertificate",
          "acm-pca:ListCertificateAuthorities"
        ]
        Resource = [
          aws_acmpca_certificate_authority.service_connect_ca.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.service_connect_tls.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.service_connect.arn}:*"
        ]
      }
    ]
  })
}

# IAM Policy for Service Discovery
resource "aws_iam_role_policy" "service_discovery" {
  name = "${var.project_name}-service-discovery-policy"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "servicediscovery:DiscoverInstances",
          "servicediscovery:GetInstancesHealthStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}