# Complete Examples Usage Guide

This guide provides step-by-step instructions for deploying and using the complete Blue/Green deployment and Service Connect with TLS examples.

## Prerequisites

Before using these examples, ensure you have:

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- A VPC with public and private subnets
- IAM permissions for ECS, CodeDeploy, ACM Private CA, and KMS operations
- `jq` tool installed (for deployment scripts)

## Blue/Green Deployment Example

### Overview
This example demonstrates zero-downtime deployments using AWS CodeDeploy with ECS Fargate services.

### Features
- ✅ Blue/Green deployments with CodeDeploy
- ✅ Application Load Balancer with dual target groups
- ✅ CloudWatch alarms for monitoring
- ✅ Auto-scaling configuration
- ✅ Automated deployment script
- ✅ SNS notifications for deployment events

### Quick Start

1. **Navigate to the Blue/Green example directory:**
   ```bash
   cd examples/blue-green-deployment/
   ```

2. **Copy and customize the variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your VPC ID and other parameters
   ```

3. **Initialize and deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Test the deployment:**
   ```bash
   # Get the load balancer URL from outputs
   terraform output application_url
   
   # Test the application
   curl $(terraform output -raw application_url)
   ```

### Deploying New Versions

Use the included deployment script for seamless blue/green deployments:

```bash
# Deploy a new version
./deploy.sh deploy nginx latest

# Check deployment status
./deploy.sh status <deployment-id>

# Rollback if needed
./deploy.sh rollback <deployment-id>
```

### Monitoring

The example includes CloudWatch alarms for:
- High CPU utilization (>80%)
- High memory utilization (>90%)
- Unhealthy target groups

View alarms in the AWS Console or via CLI:
```bash
aws cloudwatch describe-alarms --region us-west-2
```

## Service Connect with TLS Example

### Overview
This example demonstrates secure service-to-service communication using ECS Service Connect with TLS encryption.

### Features
- ✅ Service Connect with TLS encryption
- ✅ AWS Private Certificate Authority integration
- ✅ KMS-based key management
- ✅ Multi-tier architecture (API, Client, Database)
- ✅ Service discovery with DNS names
- ✅ Auto-scaling per service
- ✅ Comprehensive security groups

### Architecture

```
┌─────────────────┐    TLS     ┌─────────────────┐    TLS     ┌─────────────────┐
│   Client App    │──────────→ │   Secure API    │──────────→ │   Database      │
│                 │            │                 │            │   (PostgreSQL)  │
│ Port: 80        │            │ Port: 8443      │            │ Port: 5432      │
└─────────────────┘            └─────────────────┘            └─────────────────┘
```

### Quick Start

1. **Navigate to the Service Connect TLS example directory:**
   ```bash
   cd examples/service-connect-tls/
   ```

2. **Copy and customize the variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your VPC ID and other parameters
   ```

3. **Important: Update the database password**
   ```bash
   # Edit terraform.tfvars and change db_password to a secure value
   db_password = "YourSecurePasswordHere123!"
   ```

4. **Initialize and deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

5. **Test the deployment:**
   ```bash
   # Run health checks
   ./test-connectivity.sh health
   
   # Check specific components
   ./test-connectivity.sh services
   ./test-connectivity.sh ca
   ./test-connectivity.sh kms
   ```

### Service Communication

Services communicate using DNS names within the Service Connect namespace:

- **Client to API**: `https://secure-api.secure.local:8443`
- **API to Database**: `postgres://postgres-db.secure.local:5432`
- **Inter-service**: All communication is TLS encrypted

### Certificate Management

The example creates a private Certificate Authority that:
- Issues certificates automatically for Service Connect
- Uses KMS for key encryption
- Supports certificate rotation
- Provides end-to-end encryption

### Testing Service Connectivity

Use the included test script:

```bash
# Full health check
./test-connectivity.sh health

# Test individual components
./test-connectivity.sh cluster     # Check ECS cluster
./test-connectivity.sh services    # Check ECS services
./test-connectivity.sh ca          # Check Certificate Authority
./test-connectivity.sh kms         # Check KMS key
./test-connectivity.sh discovery   # Check service discovery
./test-connectivity.sh logs        # Check CloudWatch logs
```

### Debugging Service Connect Issues

1. **Check Service Connect logs:**
   ```bash
   aws logs tail /aws/ecs/service-connect --follow
   ```

2. **Verify certificate authority status:**
   ```bash
   aws acm-pca describe-certificate-authority --certificate-authority-arn <ca-arn>
   ```

3. **Test DNS resolution within tasks:**
   ```bash
   # Enable ECS Exec in the service configuration first
   aws ecs execute-command \
     --cluster secure-microservices-cluster \
     --task <task-arn> \
     --container client-app \
     --interactive \
     --command "/bin/sh"
   ```

## Common Configurations

### Customizing Resource Sizes

Both examples support customizable resource allocation:

```hcl
# Blue/Green example
desired_count = 3
min_capacity  = 2
max_capacity  = 20

# Service Connect TLS example
api_cpu           = 1024
api_memory        = 2048
api_desired_count = 3
```

### Adding Custom Environment Variables

```hcl
envvars = [
  {
    name  = "CUSTOM_CONFIG"
    value = "production"
  },
  {
    name  = "LOG_LEVEL"
    value = "INFO"
  }
]
```

### Configuring Auto Scaling

```hcl
autoscaling = {
  max_capacity = 10
  min_capacity = 2
  cpu_scaling_policy_configuration = {
    target_value = 70
    scale_in_cooldown = 300
    scale_out_cooldown = 300
  }
  memory_scaling_policy_configuration = {
    target_value = 80
  }
}
```

## Security Best Practices

### Blue/Green Deployment Security
- Use least-privilege IAM roles
- Enable ALB access logging
- Configure WAF rules if needed
- Use private subnets for ECS services
- Enable VPC Flow Logs

### Service Connect TLS Security
- Rotate KMS keys regularly
- Use strong database passwords
- Implement network segmentation
- Monitor certificate expiration
- Enable CloudTrail for audit logging

## Troubleshooting

### Blue/Green Deployments

**Issue**: Deployment fails during traffic switch
```bash
# Check CodeDeploy deployment details
aws deploy get-deployment --deployment-id <deployment-id>

# Check target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

**Issue**: High CPU/Memory alarms trigger rollbacks
```bash
# Check service metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=<service-name> \
  --statistics Average \
  --start-time <start-time> \
  --end-time <end-time> \
  --period 300
```

### Service Connect TLS

**Issue**: Services cannot resolve each other
```bash
# Check service discovery namespace
aws servicediscovery list-namespaces

# Verify Service Connect configuration
aws ecs describe-services --cluster <cluster-name> --services <service-name>
```

**Issue**: TLS handshake failures
```bash
# Check certificate authority status
aws acm-pca describe-certificate-authority --certificate-authority-arn <ca-arn>

# Verify KMS key permissions
aws kms describe-key --key-id <key-alias>
```

## Cost Optimization

### Blue/Green Deployment
- Use Fargate Spot for non-production environments
- Set appropriate auto-scaling thresholds
- Clean up old target groups and load balancers
- Monitor data transfer costs

### Service Connect TLS
- Right-size container resources
- Use single-AZ deployment for development
- Monitor KMS key usage charges
- Optimize log retention periods

## Next Steps

1. **Customize for your applications**: Modify container images, ports, and environment variables
2. **Add monitoring**: Integrate with your monitoring solution
3. **Implement CI/CD**: Connect with your deployment pipeline
4. **Scale horizontally**: Add more services to the examples
5. **Enhance security**: Add additional security layers as needed

For more advanced configurations and troubleshooting, refer to the individual README files in each example directory.