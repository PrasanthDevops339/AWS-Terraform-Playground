# ECS Fargate Service — Operational Runbook

## Quick Reference

| Item | Value |
|---|---|
| **Cluster** | `my-api` |
| **Service** | `my-api` |
| **Log Group** | `/ecs/my-api` |
| **Exec Log Group** | `/ecs/my-api/exec` |
| **Alarm SNS Topic** | `my-api-ecs-alerts` |

---

## Common Operations

### 1. Check Service Status

```bash
aws ecs describe-services \
  --cluster my-api \
  --services my-api \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Deployments:deployments[*].{Id:id,Status:rolloutState,TaskDef:taskDefinition}}' \
  --output table
```

### 2. ECS Exec — Shell into a Running Container

```bash
# List running tasks
aws ecs list-tasks --cluster my-api --service-name my-api --desired-status RUNNING

# Exec into a task
aws ecs execute-command \
  --cluster my-api \
  --task <TASK_ID> \
  --container api \
  --interactive \
  --command "/bin/sh"
```

### 3. Force New Deployment (No Code Change)

```bash
aws ecs update-service \
  --cluster my-api \
  --service my-api \
  --force-new-deployment
```

### 4. Scale Service Manually

```bash
aws ecs update-service \
  --cluster my-api \
  --service my-api \
  --desired-count 5
```

### 5. View Recent Logs

```bash
aws logs tail /ecs/my-api --follow --since 30m
```

### 6. Check Deployment Circuit Breaker Events

```bash
aws ecs describe-services \
  --cluster my-api \
  --services my-api \
  --query 'services[0].events[:10]' \
  --output table
```

---

## ECS-Native Deployment Operations (B/G, Linear, Canary)

### 7. Trigger Blue/Green Deployment (AWS CLI)

```bash
# Register new task definition, then:
aws ecs update-service \
  --cluster my-api \
  --service my-api \
  --task-definition my-api:42 \
  --deployment-configuration '{
    "strategy": "BLUE_GREEN",
    "deploymentCircuitBreaker": {"enable": true, "rollback": true},
    "bakeTimeInMinutes": 5
  }' \
  --force-new-deployment
```

### 8. Trigger Linear Deployment

```bash
aws ecs update-service \
  --cluster my-api \
  --service my-api \
  --task-definition my-api:42 \
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

### 9. Trigger Canary Deployment

```bash
aws ecs update-service \
  --cluster my-api \
  --service my-api \
  --task-definition my-api:42 \
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

### 10. Monitor Active B/G Deployment

```bash
# Watch deployment progress
watch -n5 'aws ecs describe-services \
  --cluster my-api \
  --services my-api \
  --query "services[0].deployments[*].{
    Id:id, Status:status, RolloutState:rolloutState,
    Running:runningCount, Desired:desiredCount,
    TaskDef:taskDefinition, Strategy:strategy}" \
  --output table'
```

### 11. Emergency Rollback — Switch Back to Previous Revision

```bash
# Option A: Let ECS handle it (if deployment still in progress)
# ECS auto-rolls back if circuit breaker or alarms trigger.

# Option B: Manual — redeploy previous task definition
PREV_TD=$(aws ecs describe-services \
  --cluster my-api \
  --services my-api \
  --query 'services[0].deployments[-1].taskDefinition' \
  --output text)

aws ecs update-service \
  --cluster my-api \
  --service my-api \
  --task-definition "${PREV_TD}" \
  --force-new-deployment

# Option C: Via GitLab — re-run the last successful deploy pipeline
```

---

## Incident Response

### Deployment Rolled Back (Circuit Breaker)

1. Check service events for the failure reason
2. Inspect failed task logs: `aws logs tail /ecs/my-api --since 1h`
3. Identify the broken task definition revision
4. Fix the image / config issue
5. Push a corrected image and re-deploy via CI/CD

### High CPU / Memory Alarm

1. Check if auto scaling has kicked in: verify running task count
2. Review Container Insights for per-task CPU/memory breakdown
3. If sustained: consider increasing `task_cpu` / `task_memory`
4. If spike: verify the scaling policy target values are appropriate

### Tasks Failing to Start

1. Check task stopped reason: `aws ecs describe-tasks --cluster my-api --tasks <TASK_ID>`
2. Common causes: ECR image pull failure, secrets access denied, port conflicts
3. Verify task execution role has required permissions
4. Check security group allows required egress (ECR, Secrets Manager, S3 endpoints)

### EFS Mount Failure

1. Verify EFS mount targets exist in the same subnets as ECS tasks
2. Check EFS security group allows NFS (2049/tcp) from ECS security group
3. Verify transit encryption is enabled if IAM auth is used
4. Check task role has `elasticfilesystem:ClientMount` and `ClientWrite` permissions

---

## Rollback Procedure

### Via Terraform

```bash
# Revert to previous task definition revision
terraform plan -target=module.ecs_fargate
terraform apply -target=module.ecs_fargate
```

### Via AWS CLI (Emergency)

```bash
# Get previous task definition
PREV_TD=$(aws ecs describe-services --cluster my-api --services my-api \
  --query 'services[0].deployments[?status==`ACTIVE`].taskDefinition' --output text)

# Update service to previous
aws ecs update-service \
  --cluster my-api \
  --service my-api \
  --task-definition $PREV_TD \
  --force-new-deployment
```

---

## SLIs / SLOs

| SLI | SLO | Alarm |
|---|---|---|
| CPU Utilization | < 80% avg over 10min | `my-api-cpu-high` |
| Memory Utilization | < 80% avg over 10min | `my-api-memory-high` |
| Running Task Count | >= 2 at all times | `my-api-low-task-count` |
| Deployment Success | Auto-rollback on failure | Circuit Breaker |
