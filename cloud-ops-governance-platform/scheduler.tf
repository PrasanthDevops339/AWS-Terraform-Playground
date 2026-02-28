resource "aws_cloudwatch_event_rule" "scheduled_task" {
  name                = "scheduled-ecs-event-rule"
  schedule_expression = "cron(0 8 1 * ? *)" # run every 6 hours
  description         = "Trigger CCOP ECS Ingest Task for getting Tag Violations from AWS Config"
}

resource "aws_cloudwatch_event_target" "scheduled_task" {
  target_id = "scheduled-target"
  rule      = aws_cloudwatch_event_rule.scheduled_task.name
  arn       = resource.aws_ecs_cluster.ecs_cluster.arn # arn of the ecs cluster to run on
  role_arn  = module.events_invoke_role.iam_role_arn

  ecs_target {
    task_definition_arn = trimsuffix(aws_ecs_task_definition.ingest_task.arn, ":${aws_ecs_task_definition.ingest_task.revision}")
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = local.subnet_list
      assign_public_ip = true
      security_groups  = [aws_security_group.security_group.id]
    }
  }
}

resource "aws_cloudwatch_event_rule" "ec2_scheduled_task" {
  name                = "scheduled-ec2-event-rule"
  schedule_expression = "cron(0 10 1 * ? *)" # run 1st of every month
  description         = "Trigger CCOP ECS EC2 Task for EC2 Inventory"
}

resource "aws_cloudwatch_event_target" "ec2_scheduled_task" {
  target_id = "scheduled-ec2-target"
  rule      = aws_cloudwatch_event_rule.ec2_scheduled_task.name
  arn       = resource.aws_ecs_cluster.ecs_cluster.arn # arn of the ecs cluster to run on
  role_arn  = module.events_invoke_role.iam_role_arn

  ecs_target {
    task_definition_arn = trimsuffix(aws_ecs_task_definition.ec2_task.arn, ":${aws_ecs_task_definition.ec2_task.revision}")
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = local.subnet_list
      assign_public_ip = true
      security_groups  = [aws_security_group.security_group.id]
    }
  }
}

resource "aws_cloudwatch_event_rule" "tagging_scheduled_task" {
  name                = "scheduled-tagging-event-rule"
  schedule_expression = "cron(0 7 ? * 2 *)" # run Monday of every week
  description         = "Trigger CCOP ECS Backup and Patch Tags Task for generating the Tag violation report for Tawfeeq"
}

resource "aws_cloudwatch_event_target" "tagging_scheduled_task" {
  target_id = "scheduled-tagging-target"
  rule      = aws_cloudwatch_event_rule.tagging_scheduled_task.name
  arn       = resource.aws_ecs_cluster.ecs_cluster.arn # arn of the ecs cluster to run on
  role_arn  = module.events_invoke_role.iam_role_arn

  ecs_target {
    task_definition_arn = trimsuffix(aws_ecs_task_definition.tagging_task.arn, ":${aws_ecs_task_definition.tagging_task.revision}")
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = local.subnet_list
      assign_public_ip = true
      security_groups  = [aws_security_group.security_group.id]
    }
  }
}