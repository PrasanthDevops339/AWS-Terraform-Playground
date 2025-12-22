# Complete Documentation for Enhanced ECS Fargate Module

This document provides comprehensive details about all the new features and capabilities added to the ECS Fargate module.

## Quick Start Examples

### 1. Multiple Services with Service Connect

```hcl
module "ecs_fargate" {
  source = "path/to/this/module"

  cluster_name = "my-cluster"
  vpc_id       = "vpc-12345678"

  service_connect_configuration = {
    enabled   = true
    namespace = "my-namespace"
  }

  container_config = {
    frontend = {
      # Frontend service configuration
    }
    backend = {
      # Backend service configuration  
    }
  }
}
```

### 2. Service Connect with TLS

```hcl
service_connect = {
  enabled = true
  services = [{
    port_name = "secure-app-port"
    tls = {
      issuer_certificate_authority = {
        aws_pca_authority_arn = "arn:aws:acm-pca:..."
      }
      kms_key  = "arn:aws:kms:..."
      role_arn = "arn:aws:iam::...role/service-connect-tls"
    }
  }]
}
```

### 3. Blue/Green Deployment with CodeDeploy

```hcl
service = {
  deployment_controller = {
    type = "CODE_DEPLOY"
  }
  codedeploy_role_arn = "arn:aws:iam::...role/codedeploy"
  blue_green_deployment_config = {
    terminate_blue_instances_on_deployment_success = {
      action = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }
}
```

## Service Connect Features

### Basic Service Connect
- Automatic service discovery
- DNS-based service communication
- Load balancing between service instances
- Health checking and circuit breaking

### Service Connect with TLS
- End-to-end encryption for service communication
- Automatic certificate management via AWS Private CA
- KMS integration for key management
- Performance optimized TLS termination

## Deployment Strategies

### 1. Rolling Updates (ECS - Default)
- **Use Case**: Standard deployments with minimal configuration
- **Benefits**: Simple, reliable, built-in circuit breaker support
- **Configuration**: Automatic with optional circuit breaker and alarms

### 2. Blue/Green Deployments (CodeDeploy)
- **Use Case**: Zero-downtime deployments with instant rollback
- **Benefits**: Complete environment isolation, automated traffic switching
- **Requirements**: CodeDeploy service role, dual target groups

### 3. External Deployment Controller
- **Use Case**: Custom deployment logic, advanced strategies
- **Benefits**: Full control, integration with external tools
- **Examples**: Canary deployments, feature flag integration

## Auto Scaling Capabilities

### CPU-Based Scaling
```hcl
cpu_scaling_policy_configuration = {
  target_value       = 70
  scale_in_cooldown  = 300
  scale_out_cooldown = 300
}
```

### Memory-Based Scaling
```hcl
memory_scaling_policy_configuration = {
  target_value = 80
}
```

### Step Scaling
```hcl
step_scaling_policy_configuration = {
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 2
  metric_interval_lower_bound = 0
}
```

## Advanced Configuration Options

### Service Registries
Support for AWS Cloud Map service discovery:

```hcl
service_registries = [{
  registry_arn   = "arn:aws:servicediscovery:..."
  container_name = "web-app"
  container_port = 80
}]
```

### Capacity Provider Strategy
Configure Fargate and Fargate Spot usage:

```hcl
capacity_provider_strategy = [{
  capacity_provider = "FARGATE_SPOT"
  weight           = 1
  base             = 0
}]
```

### Placement Constraints
Control task placement:

```hcl
placement_constraints = [{
  type = "memberOf"
  expression = "attribute:ecs.instance-type =~ t2.*"
}]
```

## Security Features

### Network Security
- VPC networking with security groups
- Private subnet deployment
- Service-to-service communication controls

### IAM Integration
- Task execution roles for AWS API access
- Task roles for application permissions
- Service Connect TLS roles for certificate management

### Encryption
- TLS encryption for service communication
- KMS key integration
- CloudWatch Logs encryption

## Monitoring and Observability

### CloudWatch Integration
- Container insights enabled by default
- Custom metrics and alarms
- Deployment monitoring and alerting

### Service Connect Logging
```hcl
log_configuration = {
  log_driver = "awslogs"
  options = {
    awslogs-group  = "/aws/ecs/service-connect"
    awslogs-region = "us-west-2"
  }
}
```

### Deployment Alarms
```hcl
alarms = {
  enable      = true
  rollback    = true
  alarm_names = ["high-cpu", "high-error-rate"]
}
```

## Migration Guide

### From Previous Version
1. **Target Groups**: Ensure all target groups are created externally
2. **Service Configuration**: Update container_config structure for new features
3. **Service Connect**: Add service_connect_configuration for inter-service communication
4. **Deployment Strategy**: Specify deployment_controller type if not using ECS default

### Best Practices
1. **Service Naming**: Use consistent naming conventions across services
2. **Resource Tagging**: Tag all resources for cost allocation and management
3. **Security Groups**: Use least-privilege security group rules
4. **Monitoring**: Enable CloudWatch Container Insights and custom alarms
5. **Auto Scaling**: Configure appropriate scaling policies based on workload patterns

## Troubleshooting

### Common Issues
1. **Service Connect DNS Resolution**: Ensure namespace is properly configured
2. **TLS Certificate Issues**: Verify AWS Private CA permissions and KMS key access
3. **CodeDeploy Failures**: Check service role permissions and target group health
4. **Auto Scaling**: Monitor CloudWatch metrics and scaling activity

### Debugging Tips
1. **ECS Service Events**: Check service events in AWS console for deployment issues
2. **CloudWatch Logs**: Enable execute command for container debugging
3. **Service Connect**: Use service connect proxy logs for connectivity issues
4. **Load Balancer**: Verify target group health and listener rules

## Performance Considerations

### Service Connect
- Uses AWS infrastructure for load balancing
- Minimal latency overhead for TLS encryption
- Automatic scaling of proxy infrastructure

### Resource Allocation
- Right-size CPU and memory allocations
- Use Fargate Spot for cost optimization on non-critical workloads
- Configure appropriate auto scaling thresholds

### Network Optimization
- Use private subnets for internal services
- Optimize security group rules for performance
- Consider service mesh alternatives for complex networking requirements

For more detailed examples and specific use cases, refer to the examples directory in this module.