#########################
# examples/complete/main.tf
#########################

module "app_container" {
  source       = "../../"
  vpc_id       = data.aws_vpc.main.id
  create_cluster = true
  cluster_name = "ecs-cluster-complete-example"

  # Wire ECS service to the TG created by the ALB module
  target_groups = [
    {
      target_group_arn = module.alb.target_groups["ex-ip"].id
      container_name   = "first-complete"
      container_port   = 80
    }
  ]

  # EFS volume presented to the task
  efs_volumes = [{
    name = "efs-html"
    efs_volume_configuration = [{
      file_system_id     = module.efs.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config = {
        iam = "ENABLED"
      }
    }]
  }]

  # ECS Exec config + CW Logs
  cluster_configuration = [{
    execute_command_configuration = {
      kms_key_id = module.kms.key_id
      logging    = "OVERRIDE"
      log_configuration = {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = module.cloudwatch.cloudwatch_log_group_name
      }
    }
  }]
  # One service definition
  container_config = {
    "first-app" = {
      container_name = "first-complete"

      service = {
        desired_count        = 1
        container_port       = 80
        enable_execute_command = true
        force_new_deployment = true
        security_groups      = [module.ecs_sg.security_group_id]
        subnets              = [element(data.aws_subnets.app_subnets.ids, 0)]
      }

      task_definition = {
        cpu                = 2048
        memory             = 4096
        execution_role_arn = module.iam_role.iam_role_arn
        task_role_arn      = module.iam_role.iam_role_arn
        host_port          = 80
        container_port     = 80
        image              = "${module.ecr.repository_url}:latest"
        task_log_group_name = module.cloudwatch.cloudwatch_log_group_name
        mode               = "non-blocking"
        max-buffer-size    = "2m"

        ephemeral_storage = {
          size_in_gib = 50
        }

        mountPoints = [{
          sourceVolume  = "efs-html"
          containerPath = "/usr/share/nginx"
        }]
      }

      autoscaling = {
        max_capacity = 3
        min_capacity = 1

        cpu_scaling_policy_configuration = {
          target_value       = 70
          scale_in_cooldown  = 300
          scale_out_cooldown = 300
        }

        memory_scaling_policy_configuration = {
          target_value       = 70
          scale_in_cooldown  = 300
          scale_out_cooldown = 300
        }
      }
    }
  }
}

# IAM role for the task/execution
module "iam_role" {
  source               = "tfe.com/iam/aws"
  trusted_role_services = ["ecs-tasks.amazonaws.com"]
  create_role          = true
  create_policy        = true
  role_name            = "ecs-iam-role-complete"
  description          = "ECS policy which will be assume by deployment account"
  policy_name          = "ecs-iam-policy-complete"
  policy               = templatefile("${path.module}/iam/policy.json", {
    kms_key_arn = module.efs_kms.key_arn
  })
}

# ECR repository for the example image
module "ecr" {
  source               = "tfe.com/ecr/aws"
  name                 = "tfe-ecs-module-complete"
  image_tag_mutability = "MUTABLE"
  repository_policy    = templatefile("./iam/ecr-policy.tpl", { iam_role_arn = module.iam_role.iam_role_arn })

  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 30
      }
      action = { type = "expire" }
    }]
  })
}

# CloudWatch log group for tasks (encrypted by module.kms)
module "cloudwatch" {
  source        = "tfe.com/cloudwatch/aws"
  depends_on    = [module.kms]
  log_group_name = "ecs-complete-logs"
  kms_key_id     = module.kms.key_arn
}
