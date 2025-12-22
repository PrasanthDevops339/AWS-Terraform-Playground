# Multiple Services with Service Connect Example

This example demonstrates deploying multiple services to the same ECS cluster with service connect enabled.

## Configuration

```hcl
module "ecs_fargate_multiple_services" {
  source = "../.."

  cluster_name = "multi-service-cluster"
  vpc_id       = "vpc-12345678"

  # Enable Service Connect
  service_connect_configuration = {
    enabled   = true
    namespace = "example-namespace"
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group  = "/aws/ecs/service-connect"
        awslogs-region = "us-west-2"
      }
    }
  }

  # Multiple services configuration
  container_config = {
    # Frontend Service
    frontend = {
      container_name = "frontend-app"
      task_definition = {
        cpu                = 512
        memory            = 1024
        image             = "nginx:latest"
        container_port    = 80
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/frontend"
      }
      service = {
        desired_count    = 2
        security_groups  = [aws_security_group.frontend.id]
        subnets         = data.aws_subnets.private.ids
        
        # Service Connect configuration
        service_connect = {
          enabled   = true
          services = [{
            port_name = "frontend-port"
            client_aliases = [{
              port     = 80
              dns_name = "frontend.local"
            }]
          }]
        }
      }
    }
    
    # Backend API Service
    backend = {
      container_name = "backend-api"
      task_definition = {
        cpu                = 256
        memory            = 512
        image             = "node:alpine"
        container_port    = 3000
        execution_role_arn = aws_iam_role.execution_role.arn
        task_role_arn     = aws_iam_role.task_role.arn
        task_log_group_name = "/aws/ecs/backend"
      }
      service = {
        desired_count    = 3
        security_groups  = [aws_security_group.backend.id]
        subnets         = data.aws_subnets.private.ids
        
        # Service Connect configuration
        service_connect = {
          enabled   = true
          services = [{
            port_name = "backend-port"
            client_aliases = [{
              port     = 3000
              dns_name = "backend.local"
            }]
          }]
        }
      }
      
      # Auto Scaling
      autoscaling = {
        max_capacity = 10
        min_capacity = 2
        cpu_scaling_policy_configuration = {
          target_value = 70
        }
        memory_scaling_policy_configuration = {
          target_value = 80
        }
      }
    }
  }

  tags = {
    Environment = "development"
    Project     = "multi-service-example"
  }
}
```

## Service Discovery

With Service Connect enabled, services can communicate using DNS names:
- Frontend can reach backend at `backend.local:3000`
- Backend can reach frontend at `frontend.local:80`

## Auto Scaling

The backend service includes auto-scaling configuration:
- Min capacity: 2 tasks
- Max capacity: 10 tasks
- CPU target: 70%
- Memory target: 80%