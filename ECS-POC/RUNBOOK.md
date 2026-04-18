# ECS Fargate POC Runbook

This runbook is a generic operational reference for the local ECS Fargate POC.
Replace placeholder names such as `my-cluster`, `my-service`, and `/ecs/my-app`
with the actual values from your environment.

## Quick Reference

Track these values before an incident:

- cluster name
- service name
- task definition family
- application log group
- exec log group
- deployment alarm names

## Common Operations

## Check Service Status

```bash
aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Deployments:deployments[*].{Id:id,Rollout:rolloutState,TaskDef:taskDefinition}}' \
  --output table
```

## List Running Tasks

```bash
aws ecs list-tasks \
  --cluster my-cluster \
  --service-name my-service \
  --desired-status RUNNING
```

## ECS Exec Into A Running Container

```bash
aws ecs execute-command \
  --cluster my-cluster \
  --task <TASK_ID> \
  --container app \
  --interactive \
  --command "/bin/sh"
```

## Force A New Deployment

```bash
aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --force-new-deployment
```

## Scale Service Manually

```bash
aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --desired-count 5
```

## Tail Logs

```bash
aws logs tail /ecs/my-app --follow --since 30m
```

## Review Recent ECS Service Events

```bash
aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --query 'services[0].events[:10]' \
  --output table
```

## ECS-Native Deployment Operations

These examples assume the service is using the ECS deployment controller and
the AWS provider-side deployment strategy features.

## Trigger Blue/Green

```bash
aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --task-definition my-service:42 \
  --deployment-configuration '{
    "strategy": "BLUE_GREEN",
    "deploymentCircuitBreaker": {"enable": true, "rollback": true},
    "bakeTimeInMinutes": 5
  }' \
  --force-new-deployment
```

## Trigger Linear

```bash
aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --task-definition my-service:42 \
  --deployment-configuration '{
    "strategy": "LINEAR",
    "deploymentCircuitBreaker": {"enable": true, "rollback": true},
    "bakeTimeInMinutes": 5,
    "linearConfiguration": {
      "stepPercent": 10,
      "stepBakeTimeInMinutes": 3
    }
  }' \
  --force-new-deployment
```

## Trigger Canary

```bash
aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --task-definition my-service:42 \
  --deployment-configuration '{
    "strategy": "CANARY",
    "deploymentCircuitBreaker": {"enable": true, "rollback": true},
    "bakeTimeInMinutes": 5,
    "canaryConfiguration": {
      "canaryPercent": 10,
      "canaryBakeTimeInMinutes": 10
    }
  }' \
  --force-new-deployment
```

## Monitor Active Deployment

```bash
watch -n5 'aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --query "services[0].deployments[*].{
    Id:id,Status:status,RolloutState:rolloutState,
    Running:runningCount,Desired:desiredCount,
    TaskDef:taskDefinition}" \
  --output table'
```

## Incident Response

## Deployment Rolled Back

1. Check ECS service events for the failure reason.
2. Inspect recent application and proxy logs.
3. Confirm which task definition revision failed.
4. Verify alarms, listener rules, and target group health if traffic shifting
   was involved.
5. Re-deploy a corrected image or revert to the previous task definition.

## Tasks Failing To Start

Check:

- task stopped reason
- image pull permissions
- secrets access
- subnet routing and security group egress
- log group existence
- target group health checks for LB-backed services

Useful command:

```bash
aws ecs describe-tasks \
  --cluster my-cluster \
  --tasks <TASK_ID>
```

## High CPU Or Memory

Check:

- current desired and running task count
- recent scale-out activity
- Container Insights or CloudWatch metrics
- whether task CPU and memory sizing are still appropriate

## EFS Mount Failure

Check:

- EFS mount targets in reachable subnets
- EFS security group allowing `2049/tcp`
- transit encryption requirements
- task role permissions for EFS IAM auth

## Rollback

## Via Terraform

Use the normal Terraform workflow after restoring the desired image tag or task
definition inputs:

```bash
terraform plan
terraform apply
```

## Via AWS CLI

```bash
PREV_TD=$(aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --query 'services[0].deployments[-1].taskDefinition' \
  --output text)

aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --task-definition "${PREV_TD}" \
  --force-new-deployment
```

## Operating Notes

- Keep the cluster name, service names, log groups, and alarm names written
  down before you need them.
- Prefer Terraform as the source of truth for steady-state configuration.
- Use direct AWS CLI service updates for incident response only, then reconcile
  state back into Terraform.
