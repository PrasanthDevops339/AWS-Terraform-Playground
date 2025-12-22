# External Deployment Controller Example

This example demonstrates using an external deployment controller for advanced deployment patterns.

## Configuration

```hcl
module "ecs_fargate_external_deployment" {
  source = "../.."

  cluster_name = "external-deploy-cluster"
  vpc_id       = "vpc-12345678"

  container_config = {
    microservice_a = {
      container_name = "microservice-a"
      task_definition = {
        cpu                = 256
        memory            = 512
        image             = "microservice-a:latest"
        container_port    = 8080
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/microservice-a"
      }
      service = {
        desired_count    = 2
        security_groups  = [aws_security_group.microservice_a.id]
        subnets         = data.aws_subnets.private.ids
        
        # External Deployment Controller
        deployment_controller = {
          type = "EXTERNAL"
        }
      }
    }
    
    microservice_b = {
      container_name = "microservice-b"
      task_definition = {
        cpu                = 256
        memory            = 512
        image             = "microservice-b:latest"
        container_port    = 8081
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/microservice-b"
      }
      service = {
        desired_count    = 3
        security_groups  = [aws_security_group.microservice_b.id]
        subnets         = data.aws_subnets.private.ids
        
        # External Deployment Controller
        deployment_controller = {
          type = "EXTERNAL"
        }
      }
    }
  }

  tags = {
    Environment      = "production"
    DeploymentType   = "external"
    OrchestrationTool = "custom"
  }
}

# Example: Custom deployment orchestration using AWS Lambda
resource "aws_lambda_function" "deployment_orchestrator" {
  filename         = "deployment_orchestrator.zip"
  function_name    = "ecs-deployment-orchestrator"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.deployment_orchestrator.output_base64sha256
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      CLUSTER_NAME = module.ecs_fargate_external_deployment.cluster_name
      SERVICES     = jsonencode(keys(var.container_config))
    }
  }

  tags = {
    Name = "ECS Deployment Orchestrator"
  }
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "ecs-deployment-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda policy for ECS operations
resource "aws_iam_role_policy" "lambda_ecs_policy" {
  name = "lambda-ecs-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.execution_role.arn,
          aws_iam_role.task_role.arn
        ]
      }
    ]
  })
}

# EventBridge rule to trigger deployments
resource "aws_cloudwatch_event_rule" "deployment_trigger" {
  name        = "ecs-deployment-trigger"
  description = "Trigger ECS deployments based on custom events"

  event_pattern = jsonencode({
    source      = ["custom.deployment"]
    detail-type = ["ECS Deployment Request"]
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.deployment_trigger.name
  target_id = "TriggerLambda"
  arn       = aws_lambda_function.deployment_orchestrator.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deployment_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deployment_trigger.arn
}

# Example deployment orchestrator Lambda function
data "archive_file" "deployment_orchestrator" {
  type        = "zip"
  output_path = "deployment_orchestrator.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os

ecs = boto3.client('ecs')

def handler(event, context):
    """
    Custom deployment orchestrator for ECS services with external deployment controller.
    This function implements canary, rolling, or other custom deployment strategies.
    """
    
    cluster_name = os.environ['CLUSTER_NAME']
    services = json.loads(os.environ['SERVICES'])
    
    # Extract deployment details from event
    detail = event.get('detail', {})
    deployment_type = detail.get('deploymentType', 'rolling')
    service_name = detail.get('serviceName')
    new_task_definition = detail.get('taskDefinition')
    
    print(f"Starting {deployment_type} deployment for service {service_name}")
    
    if deployment_type == 'canary':
        return handle_canary_deployment(cluster_name, service_name, new_task_definition)
    elif deployment_type == 'rolling':
        return handle_rolling_deployment(cluster_name, service_name, new_task_definition)
    else:
        return {
            'statusCode': 400,
            'body': json.dumps(f'Unsupported deployment type: {deployment_type}')
        }

def handle_canary_deployment(cluster_name, service_name, task_definition_arn):
    """Implement canary deployment strategy"""
    try:
        # Get current service configuration
        response = ecs.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )
        
        current_service = response['services'][0]
        current_desired_count = current_service['desiredCount']
        
        # Phase 1: Deploy canary (10% of traffic)
        canary_count = max(1, current_desired_count // 10)
        
        # Update service with new task definition and canary count
        ecs.update_service(
            cluster=cluster_name,
            service=service_name,
            taskDefinition=task_definition_arn,
            desiredCount=canary_count
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Canary deployment started for {service_name}',
                'canaryCount': canary_count,
                'originalCount': current_desired_count
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error in canary deployment: {str(e)}')
        }

def handle_rolling_deployment(cluster_name, service_name, task_definition_arn):
    """Implement rolling deployment strategy"""
    try:
        # Standard rolling update
        ecs.update_service(
            cluster=cluster_name,
            service=service_name,
            taskDefinition=task_definition_arn
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Rolling deployment started for {service_name}')
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error in rolling deployment: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}
```

## Custom Deployment Strategies

With external deployment controllers, you can implement:

### 1. Canary Deployments
- Deploy new version to small subset of tasks
- Monitor metrics and health
- Gradually increase traffic to new version

### 2. Feature Flags Integration
- Deploy multiple versions simultaneously
- Route traffic based on feature flags
- A/B testing capabilities

### 3. Multi-Region Deployments
- Coordinate deployments across regions
- Implement circuit breaker patterns
- Global traffic management

### 4. Custom Health Checks
- Advanced health validation beyond ECS health checks
- Integration with external monitoring systems
- Custom rollback triggers

## Usage

Trigger a deployment by sending an EventBridge event:

```bash
aws events put-events --entries '[
  {
    "Source": "custom.deployment",
    "DetailType": "ECS Deployment Request",
    "Detail": "{\"deploymentType\":\"canary\",\"serviceName\":\"microservice-a\",\"taskDefinition\":\"arn:aws:ecs:region:account:task-definition/microservice-a:2\"}"
  }
]'
```

## Benefits

- **Full Control**: Complete control over deployment process
- **Custom Logic**: Implement business-specific deployment requirements
- **Integration**: Easy integration with CI/CD pipelines and monitoring tools
- **Flexibility**: Support for any deployment pattern or strategy

## Prerequisites

- Lambda function with ECS permissions
- EventBridge rules for triggering deployments
- Custom monitoring and health check implementation
- CI/CD pipeline integration