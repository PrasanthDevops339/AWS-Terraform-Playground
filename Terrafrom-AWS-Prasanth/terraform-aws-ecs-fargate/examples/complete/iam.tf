########################################
# examples/complete/iam.tf
#
# Per-tier task execution + task IAM roles.
# Each module exposes:
#   execution_role_arn  — used by ECS agent to pull images + secrets
#   task_role_arn       — used by the running container (app permissions)
#
# Also creates the ECS ALB service role required for
# ECS-native CANARY/LINEAR/BLUE_GREEN traffic shifting on the api tier.
########################################

########################################
# Frontend — execution + task roles
########################################

module "iam_frontend" {
  source = "tfe.com/iam/aws"

  trusted_role_services = ["ecs-tasks.amazonaws.com"]
  create_role           = true
  create_policy         = true

  role_name   = "${var.environment}-frontend-exec-role"
  description = "ECS task execution role for the frontend tier"
  policy_name = "${var.environment}-frontend-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMParameters"
        Effect = "Allow"
        Action = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = [
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/frontend/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.environment}/frontend:*"
      }
    ]
  })
}

########################################
# API — execution + task roles
########################################

module "iam_api" {
  source = "tfe.com/iam/aws"

  trusted_role_services = ["ecs-tasks.amazonaws.com"]
  create_role           = true
  create_policy         = true

  role_name   = "${var.environment}-api-exec-role"
  description = "ECS task execution + task role for the api tier"
  policy_name = "${var.environment}-api-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMParameters"
        Effect = "Allow"
        Action = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = [
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/api/*"
        ]
      },
      {
        Sid    = "EFSAccess"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = module.efs.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.environment}/api:*"
      }
    ]
  })

  # ECS ALB service role ARN is surfaced as an output for use in main.tf
  # It is created as a separate resource below.
  extra_outputs = {
    ecs_alb_service_role_arn = aws_iam_role.ecs_alb_service.arn
  }
}

########################################
# ECS ALB service role — required for ECS-native
# CANARY / LINEAR / BLUE_GREEN traffic shifting.
# Must trust elasticloadbalancing.amazonaws.com.
########################################

resource "aws_iam_role" "ecs_alb_service" {
  name        = "${var.environment}-ecs-alb-service-role"
  description = "Allows ECS to manage ALB target group registration during canary deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_alb_service" {
  role       = aws_iam_role.ecs_alb_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

########################################
# Worker — execution + task roles
########################################

module "iam_worker" {
  source = "tfe.com/iam/aws"

  trusted_role_services = ["ecs-tasks.amazonaws.com"]
  create_role           = true
  create_policy         = true

  role_name   = "${var.environment}-worker-exec-role"
  description = "ECS task execution + task role for the worker tier"
  policy_name = "${var.environment}-worker-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = "arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:${var.environment}-jobs"
      },
      {
        Sid    = "SSMParameters"
        Effect = "Allow"
        Action = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = [
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/worker/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.environment}/worker:*"
      }
    ]
  })
}
