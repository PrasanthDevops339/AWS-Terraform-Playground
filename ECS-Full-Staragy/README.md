# Terraform AWS ECS Fargate Complete Module

> **A fully-packed, production-grade Terraform module for AWS ECS Fargate** covering every AWS ECS offering — ECS-native Blue/Green, Linear, and Canary deployments (provider >= 6.4.0), Service Connect, deployment circuit breaker, alarm-based rollback, auto scaling, EFS volumes, ECS Exec, FireLens sidecars, Graviton (ARM64) runtime, GitLab CI/CD pipeline, and CloudWatch observability.

## Features Covered

| AWS ECS Feature | Module Support | Variable |
|---|---|---|
| **ECS Cluster** | Create or use existing | `create_cluster`, `cluster_arn` |
| **Container Insights** | Enabled by default | `container_insights` |
| **Fargate + Fargate Spot** | Weighted capacity strategy | `capacity_providers`, `default_capacity_provider_strategy` |
| **Service Connect** | Full mesh config + TLS | `service_connect_configuration` |
| **Deployment Circuit Breaker** | Enable + auto-rollback | `deployment_circuit_breaker` |
| **Deployment Alarms** | CloudWatch alarm-based rollback | `deployment_alarms` |
| **Rolling Update Config** | min/max healthy percent | `deployment_minimum_healthy_percent`, `deployment_maximum_percent` |
| **🆕 Blue/Green (ECS-Native)** | Zero-downtime B/G with bake time | `deployment_strategy`, `blue_green_config` |
| **🆕 Linear (ECS-Native)** | Gradual % traffic shift | `deployment_strategy`, `linear_config` |
| **🆕 Canary (ECS-Native)** | Small % canary → full cutover | `deployment_strategy`, `canary_config` |
| **Green Target Group** | Auto-created for B/G/Linear/Canary | `create_green_target_group`, `green_target_group` |
| **GitLab CI/CD Pipeline** | Full pipeline + deploy script | `ci/.gitlab-ci.yml`, `scripts/ecs-deploy.sh` |
| **Auto Scaling — CPU** | Target tracking | `autoscaling.cpu_target` |
| **Auto Scaling — Memory** | Target tracking | `autoscaling.memory_target` |
| **Auto Scaling — ALB Requests** | Target tracking | `autoscaling.alb_request_count_target` |
| **Auto Scaling — Scheduled** | Cron-based scaling | `autoscaling.scheduled_actions` |
| **Auto Scaling — Step** | Step scaling policies | `autoscaling.step_scaling_policies` |
| **EFS Volumes** | With transit encryption + IAM auth | `efs_volumes` |
| **Bind Mount Volumes** | Sidecar sharing | `bind_mount_volumes` |
| **Docker Volumes** | Driver config | `docker_volumes` |
| **Ephemeral Storage** | 21–200 GiB | `task_ephemeral_storage_gib` |
| **ECS Exec** | Interactive debugging | `enable_execute_command` |
| **ARM64 / Graviton** | Runtime platform config | `runtime_platform` |
| **Container Health Checks** | In container definitions | `container_definitions[].healthCheck` |
| **Secrets Manager / SSM** | Secrets injection | `container_definitions[].secrets` |
| **FireLens (Fluent Bit)** | Log routing sidecar | `container_definitions[].firelensConfiguration` |
| **CloudWatch Logging** | Auto-injected per container | `create_cloudwatch_log_group` |
| **CloudWatch Alarms** | CPU, Memory, Task Count | `enable_cloudwatch_alarms` |
| **Load Balancer** | ALB/NLB target group binding | `load_balancer_config` |
| **Service Discovery** | Cloud Map DNS | `service_discovery` |
| **Security Group** | Auto-create with least privilege | `create_security_group` |
| **IAM — Task Execution Role** | ECR pull, Secrets, Logs | `create_task_execution_role` |
| **IAM — Task Role** | App permissions + ECS Exec | `create_task_role` |
| **Tagging & Propagation** | Service → Task propagation | `propagate_tags`, `enable_ecs_managed_tags` |

---

## Architecture Diagrams

### HLD — High-Level Design

```mermaid
flowchart LR
    User((User)) --> DNS[Route53<br/>DNS]
    DNS --> WAF[AWS WAF]
    WAF --> ALB[ALB<br/>HTTPS:443]

    ALB --> SvcConnect{Service Connect<br/>Proxy}
    SvcConnect --> ECS_API[ECS Fargate<br/>API Service]
    SvcConnect --> ECS_WORKER[ECS Fargate<br/>Worker Service]

    ECS_API --> RDS[(RDS<br/>PostgreSQL)]
    ECS_API --> REDIS[(ElastiCache<br/>Redis)]
    ECS_API --> SQS[SQS Queue]
    SQS --> ECS_WORKER
    ECS_WORKER --> S3[(S3 Bucket)]

    ECS_API --> EFS[(EFS<br/>Shared Storage)]
    ECS_WORKER --> EFS

    subgraph Observability
        CW[CloudWatch<br/>Logs + Metrics]
        ALARM[CloudWatch<br/>Alarms]
        SNS[SNS<br/>Notifications]
    end

    ECS_API --> CW
    ECS_WORKER --> CW
    CW --> ALARM --> SNS

    subgraph AutoScaling[Auto Scaling]
        CPU_TT[CPU Target<br/>Tracking]
        MEM_TT[Memory Target<br/>Tracking]
        ALB_TT[ALB Request<br/>Count Tracking]
        SCHED[Scheduled<br/>Scaling]
    end

    ALARM -.-> AutoScaling

    subgraph DeploymentSafety[Deployment Safety]
        CB[Circuit Breaker<br/>+ Rollback]
        DA[Deployment Alarms<br/>+ Rollback]
    end

    subgraph Cluster[ECS Cluster]
        direction TB
        FARGATE[FARGATE<br/>Capacity Provider]
        FARGATE_SPOT[FARGATE_SPOT<br/>Capacity Provider]
        ECS_API
        ECS_WORKER
    end

    style Cluster fill:#232F3E,color:#fff
    style Observability fill:#1B660F,color:#fff
    style AutoScaling fill:#8C4FFF,color:#fff
    style DeploymentSafety fill:#D13212,color:#fff
```

### LLD — Low-Level Design

```mermaid
flowchart TB
    subgraph VPC["VPC 10.0.0.0/16"]
        subgraph PublicSubnets["Public Subnets (Multi-AZ)"]
            ALB["ALB<br/>SG: 443 from 0.0.0.0/0<br/>→ TG: 8080 to ECS"]
        end

        subgraph PrivateSubnets["Private Subnets (Multi-AZ)"]
            subgraph ECSCluster["ECS Cluster: my-api"]
                direction TB
                CP_FG["Capacity Provider: FARGATE<br/>Weight: 70, Base: 1"]
                CP_SPOT["Capacity Provider: FARGATE_SPOT<br/>Weight: 30"]

                subgraph TaskDef["Task Definition: my-api"]
                    direction LR
                    SC_PROXY["Service Connect<br/>Envoy Proxy<br/>Port: 8080"]
                    APP["Container: api<br/>Image: my-api:latest<br/>CPU: 768 / Mem: 1536<br/>Port: 8080/tcp (http)<br/>RO Root FS: true<br/>Init Process: true<br/>Health: /health"]
                    SIDECAR["Container: log-router<br/>Image: aws-for-fluent-bit<br/>CPU: 256 / Mem: 512<br/>FireLens: fluentbit"]
                end

                subgraph Service["ECS Service: my-api"]
                    DEPLOY_CFG["Deploy Config:<br/>Max: 200% / Min: 100%<br/>Circuit Breaker: ON<br/>Auto-Rollback: ON"]
                    EXEC["ECS Exec: Enabled<br/>Logging: CloudWatch"]
                end
            end

            subgraph EFSMount["EFS Mount Targets"]
                EFS_MT["EFS: fs-xxx<br/>SG: 2049 from ECS SG<br/>Transit Encryption: ON<br/>IAM Auth: ON"]
            end
        end

        subgraph DataSubnets["Data Subnets"]
            RDS["RDS PostgreSQL<br/>SG: 5432 from ECS SG"]
        end
    end

    %% Connections
    ALB -->|"TCP:8080"| SC_PROXY
    SC_PROXY -->|"localhost:8080"| APP
    APP -->|"NFS:2049 (TLS)"| EFS_MT
    APP -->|"TCP:5432"| RDS
    SIDECAR -.->|"stdout/stderr"| CW_LOGS

    %% External Services
    subgraph IAM["IAM Roles"]
        EXEC_ROLE["Task Execution Role<br/>• AmazonECSTaskExecutionRolePolicy<br/>• SecretsManager:GetSecretValue<br/>• SSM:GetParameter<br/>• ECR:BatchGetImage"]
        TASK_ROLE["Task Role<br/>• SSMMessages (ECS Exec)<br/>• S3:Get/Put/List<br/>• SQS:Send/Receive/Delete<br/>• EFS:ClientMount/Write<br/>• CloudWatch:PutLogs"]
    end

    subgraph Monitoring["CloudWatch"]
        CW_LOGS["Log Groups:<br/>/ecs/my-api<br/>/ecs/my-api/exec<br/>/ecs/my-api/service-connect"]
        CW_ALARMS["Alarms:<br/>• CPU ≥ 80%<br/>• Memory ≥ 80%<br/>• TaskCount < 2"]
        SNS_TOPIC["SNS: my-api-ecs-alerts"]
    end

    subgraph Scaling["Auto Scaling"]
        AS_TARGET["Target: ecs:service:DesiredCount<br/>Min: 2 / Max: 20"]
        AS_CPU["CPU ≤ 65%"]
        AS_MEM["Memory ≤ 75%"]
        AS_ALB["ALB Req/Target ≤ 1000"]
        AS_NIGHT["Cron: 22:00 AEST → 1-5"]
        AS_MORNING["Cron: 07:00 AEST → 2-20"]
    end

    CW_ALARMS --> SNS_TOPIC
    CW_ALARMS -.->|"Deployment Alarm<br/>Rollback"| DEPLOY_CFG
    AS_TARGET --> AS_CPU & AS_MEM & AS_ALB
    AS_TARGET --> AS_NIGHT & AS_MORNING

    style VPC fill:#E7F6F8,color:#000
    style ECSCluster fill:#232F3E,color:#fff
    style IAM fill:#DD344C,color:#fff
    style Monitoring fill:#1B660F,color:#fff
    style Scaling fill:#8C4FFF,color:#fff
```

### Deployment Strategies — ECS-Native (Terraform provider >= 6.4.0)

> **No CodeDeploy required. 100% Terraform-native.** All strategies use the ECS service's
> built-in deployment engine via `deployment_configuration.strategy`.
> Just `terraform apply` — no AWS CLI workarounds.

```mermaid
flowchart TB
    subgraph Strategies["🎯 ECS-Native Deployment Strategies"]
        direction TB

        ROLLING["<b>ROLLING</b><br/>Classic rolling update<br/>min_healthy=100%, max=200%<br/>Circuit breaker + alarm rollback"]

        BG["<b>BLUE/GREEN</b><br/>Full env alongside old<br/>All-at-once traffic shift<br/>Bake time → auto-retire blue"]

        LINEAR["<b>LINEAR</b><br/>Gradual traffic shift<br/>e.g. 10% every 5 min<br/>Step bake between shifts"]

        CANARY["<b>CANARY</b><br/>Small % canary first<br/>e.g. 10% for 10 min<br/>Then full cutover + bake"]
    end

    subgraph Safety["🛡️ Safety Nets (All Strategies)"]
        CB["Circuit Breaker<br/>Auto-rollback on failure"]
        ALARM["CloudWatch Alarms<br/>CPU/Memory/Custom"]
        HOOKS["Lifecycle Hooks<br/>Lambda validation"]
    end

    ROLLING --> CB
    BG --> CB
    BG --> HOOKS
    LINEAR --> ALARM
    CANARY --> ALARM
    CANARY --> HOOKS

    style ROLLING fill:#4CAF50,color:#fff
    style BG fill:#2196F3,color:#fff
    style LINEAR fill:#FF9800,color:#fff
    style CANARY fill:#9C27B0,color:#fff
```

### Blue/Green Deployment Flow

```mermaid
sequenceDiagram
    participant GL as GitLab CI
    participant ECR as ECR
    participant ECS as ECS Service
    participant ALB as ALB
    participant TG1 as Blue TG<br/>(current)
    participant TG2 as Green TG<br/>(new)
    participant CW as CloudWatch
    participant Lambda as Lifecycle Hook

    GL->>ECR: 1. Push image :v2.0
    GL->>ECS: 2. aws ecs update-service<br/>strategy=BLUE_GREEN

    Note over ECS: Phase 1: Scale Up Green
    ECS->>TG2: 3. Register new tasks (v2.0)
    ECS->>TG2: 4. Health check passes
    ECS->>Lambda: 5. PRE_TRAFFIC_SHIFT hook (optional)
    Lambda-->>ECS: ✅ Validation passed

    Note over ECS: Phase 2: Traffic Shift
    ECS->>ALB: 6. Shift 100% traffic → Green TG
    ALB->>TG2: All production traffic

    Note over ECS: Phase 3: Bake Time
    ECS->>CW: 7. Monitor for N minutes
    CW-->>ECS: No alarms triggered

    alt Bake Succeeds
        ECS->>TG1: 8. Drain & terminate blue tasks
        ECS-->>GL: ✅ COMPLETED
    else Alarm/Hook Fails
        ECS->>ALB: Shift traffic back → Blue TG
        ECS->>TG2: Terminate green tasks
        ECS-->>GL: ❌ ROLLED BACK
    end
```

### Linear + Canary Deployment Flow

```mermaid
sequenceDiagram
    participant GL as GitLab CI
    participant ECS as ECS Service
    participant ALB as ALB
    participant CW as CloudWatch

    GL->>ECS: aws ecs update-service<br/>strategy=LINEAR or CANARY

    Note over ECS: LINEAR: 10% → 20% → ... → 100%<br/>CANARY: 10% → bake → 100%

    loop Each Traffic Step
        ECS->>ALB: Shift N% traffic to new revision
        ECS->>CW: Monitor during step bake time
        alt Step Healthy
            Note over ECS: Continue to next step
        else Alarm Triggered
            ECS->>ALB: Rollback all traffic to old revision
            ECS-->>GL: ❌ ROLLED BACK at step N
        end
    end

    Note over ECS: Final Bake Time
    ECS->>CW: Monitor full traffic on new revision
    ECS-->>GL: ✅ COMPLETED
```

### GitLab CI/CD Pipeline Flow

```mermaid
flowchart LR
    subgraph GitLab["GitLab CI/CD Pipeline"]
        direction LR
        BUILD["🐳 build<br/>Docker → ECR"]
        VALIDATE["✅ validate<br/>tf fmt + validate"]
        PLAN["📋 plan<br/>terraform plan"]
        APPLY["🏗️ apply<br/>terraform apply<br/>(manual gate)"]
        DEPLOY["🚀 deploy<br/>ecs-deploy.sh<br/>ROLLING / B/G /<br/>LINEAR / CANARY"]
    end

    BUILD --> VALIDATE --> PLAN --> APPLY --> DEPLOY

    subgraph AWS["AWS"]
        ECR["ECR"]
        TF_STATE["S3 State"]
        ECS["ECS Fargate"]
    end

    BUILD -.-> ECR
    PLAN -.-> TF_STATE
    DEPLOY -.-> ECS

    style DEPLOY fill:#2196F3,color:#fff
```

### Strategy Selection Guide

| Criteria | ROLLING | BLUE_GREEN | LINEAR | CANARY |
|---|---|---|---|---|
| **Risk tolerance** | Medium | Low | Low | Lowest |
| **Rollback speed** | ~30s (new tasks) | Instant (traffic shift) | Instant | Instant |
| **Extra cost during deploy** | ~2x tasks briefly | 2x tasks + bake time | Gradual ramp | Minimal canary |
| **Validation approach** | Health check only | Bake time + hooks | Step monitoring | Canary monitoring |
| **Terraform support** | ✅ Native | ✅ Native (>= 6.4.0) | ✅ Native | ✅ Native |
| **AWS CLI / GitLab CI** | ✅ Full | ✅ Full (July 2025) | ✅ Full (Oct 2025) | ✅ Full (Oct 2025) |
| **Best for** | Dev / low-risk | Production APIs | Progressive rollout | Critical services |
| **Recommended env** | dev, staging | staging, prod | prod | prod |

> **💡 Recommendation:** Use `ROLLING` in dev/staging for fast iteration, `BLUE_GREEN` or `CANARY`
> in production for zero-downtime safety. Just change `deployment_strategy` in your Terraform
> variables — `terraform apply` handles everything, including ALB traffic shifting.

---

## Quick Start

### 1. Terraform — Provision Infrastructure

```hcl
module "ecs_fargate" {
  source = "path/to/terraform-aws-ecs-fargate-complete"

  name        = "my-api"
  environment = "prod"

  # Networking
  vpc_id     = "vpc-abc123"
  subnet_ids = ["subnet-1", "subnet-2"]

  # Container
  task_cpu    = 512
  task_memory = 1024

  container_definitions = [
    {
      name      = "api"
      image     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api:latest"
      essential = true
      portMappings = [{
        name          = "api"
        containerPort = 8080
        protocol      = "tcp"
        appProtocol   = "http"
      }]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ]

  # Deployment Strategy — 100% Terraform-native (provider >= 6.4.0)
  deployment_strategy = "BLUE_GREEN"  # or ROLLING, LINEAR, CANARY

  # Bake time: monitor for 5 min after traffic shift before retiring old tasks
  bake_time_in_minutes = 5

  # Green target group for B/G traffic shifting
  create_green_target_group = true
  green_target_group = {
    port     = 8080
    protocol = "HTTP"
    health_check = {
      path = "/health"
    }
  }

  # ALB integration for B/G
  blue_green_config = {
    production_listener_rule = aws_lb_listener_rule.prod.arn
  }

  # Load balancer — Blue (primary) target group
  load_balancer_config = [{
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "api"
    container_port   = 8080
  }]

  # Deployment Safety (all strategies)
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }

  # Auto Scaling
  autoscaling = {
    enabled      = true
    min_capacity = 2
    max_capacity = 10
    cpu_target = {
      target_value = 70
    }
  }
}
```

### 2. GitLab CI — Build + Apply + Deploy

The pipeline builds the image, runs `terraform apply` (which sets the strategy natively),
then triggers a `force-new-deployment` to roll out the new image.

```bash
# Pipeline stages:
# build      → Docker image → ECR
# validate   → terraform fmt + validate
# plan       → terraform plan (includes deployment_strategy config)
# apply      → terraform apply (manual gate) — sets B/G/Linear/Canary natively
# deploy     → force-new-deployment (optional, for image-only updates)
```

### 3. Switching Strategies — Just Change the Variable

```hcl
# Switch to Linear: 25% every 5 min
deployment_strategy = "LINEAR"
linear_config = {
  step_percent              = 25.0
  step_bake_time_in_minutes = 5
}

# Switch to Canary: 10% canary for 10 min
deployment_strategy = "CANARY"
canary_config = {
  canary_percent              = 10.0
  canary_bake_time_in_minutes = 10
}
```

Then just `terraform apply` — ECS handles the rest.

---

## Module Structure

```
terraform-aws-ecs-fargate-complete/
├── main.tf              # All resources — ECS service with native deployment_configuration,
│                        #   green TG, ECS ALB service role, cluster, task def, IAM, SG, scaling
├── variables.tf         # Input variables — deployment_strategy, blue_green_config, linear_config,
│                        #   canary_config, lifecycle_hooks, bake_time_in_minutes
├── outputs.tf           # Resource ARNs, green TG, ECS ALB service role, deployment_strategy
├── versions.tf          # Terraform >= 1.5.0, AWS provider >= 6.4.0 (ECS-native strategies)
├── README.md            # This file — HLD/LLD diagrams, strategy guide, quick start
├── scripts/
│   └── ecs-deploy.sh    # 🔧 Emergency CLI deploy helper (for image-only updates outside TF)
├── ci/
│   └── .gitlab-ci.yml   # 🔄 GitLab CI/CD pipeline template (build → plan → apply → deploy)
├── examples/
│   └── complete/
│       └── main.tf      # Full-featured example with B/G, lifecycle hooks, ALB, EFS, Graviton
└── docs/
    └── RUNBOOK.md        # Operational runbook — deploy, rollback, incident response
```

---

## Requirements

| Name | Version |
|---|---|
| Terraform | >= 1.5.0 |
| AWS Provider | >= 5.40.0 |

---

## Definition of Done

- [ ] HLD approved by Solution Architect / CCoE
- [ ] LLD approved by peer review
- [ ] IaC merged to main branch with versioned release
- [ ] CI/CD pipeline green across all environments
- [ ] Monitoring dashboards created
- [ ] Runbook documented and accessible
- [ ] KT / handoff session completed
- [ ] Rollback procedure tested
- [ ] Tags and naming standards verified
- [ ] Security review complete
