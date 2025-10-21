# AWS Terraform Playground

A comprehensive collection of production-ready Terraform modules and AWS Service Control Policies (SCPs) for building secure, scalable AWS infrastructure.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Terraform Playground                    │
├─────────────────────┬───────────────────┬─────────────────────┤
│                     │                   │                     │
│  🏢 Governance       │  ⚙️ Infrastructure │  📋 Configuration   │
│                     │                   │                     │
│  ┌─────────────────┐ │  ┌──────────────┐ │  ┌─────────────────┐ │
│  │ Service Control │ │  │ ECS Fargate  │ │  │ Variables       │ │
│  │ Policies (SCPs) │ │  │ Clusters     │ │  │ & Outputs       │ │
│  └─────────────────┘ │  └──────────────┘ │  └─────────────────┘ │
│                     │                   │                     │
│  🔒 Block BYOL       │  ┌──────────────┐ │  📖 Examples        │
│  Licensing          │  │ Lambda       │ │  & Documentation    │
│                     │  │ Functions    │ │                     │
│                     │  └──────────────┘ │                     │
│                     │                   │                     │
│                     │  ┌──────────────┐ │                     │
│                     │  │ RDS          │ │                     │
│                     │  │ Databases    │ │                     │
│                     │  └──────────────┘ │                     │
└─────────────────────┴───────────────────┴─────────────────────┘
```

## 📁 Repository Structure

```
AWS-Terraform-Playground/
├── 📄 README.md                          # This file
├── 📄 INDEX.md                           # Detailed navigation guide
├── 🔐 aws-scp-policys/                   # AWS Service Control Policies
│   ├── 📄 README.md                      # SCP documentation
│   └── 📝 block-rds-byol.json           # BYOL license blocking policy
└── ⚙️ Terrafrom-AWS-Prasanth/            # Terraform modules
    ├── 🐳 terraform-aws-ecs-fargate/     # ECS Fargate module
    ├── ⚡ terraform-aws-lambda/          # Lambda function module
    ├── 📁 terraform-aws-lambda-old/      # Legacy Lambda module
    └── 🗄️ terraform-aws-rds/             # RDS database module
```

## 🚀 Infrastructure Components

### 🐳 ECS Fargate Module
Deploy containerized applications on AWS Fargate with automatic scaling and load balancing.

**Key Features:**
- 🎯 Application Load Balancer integration
- 📊 Auto-scaling capabilities
- 🔒 VPC security groups
- 📈 CloudWatch logging
- 🎮 ECS Exec support

### ⚡ Lambda Function Module
Serverless function deployment with comprehensive configuration options.

**Key Features:**
- 📦 Automatic packaging and deployment
- 🗂️ S3 upload support
- 🔗 Event source mapping
- 🌐 VPC configuration
- 📋 Environment variables
- 💀 Dead letter queues
- 📊 CloudWatch logging

### 🗄️ RDS Database Module
Multi-engine database deployment with high availability and backup strategies.

**Supported Engines:**
- 🐘 PostgreSQL
- 🐬 MySQL
- 🔶 Oracle Database
- 🏢 Microsoft SQL Server

**Key Features:**
- 🔄 Cross-region backup
- 📖 Read replicas
- 🔒 Encryption at rest
- 📊 Performance Insights
- 🎛️ Parameter groups
- 🔧 Option groups

### 🔐 Service Control Policies (SCPs)
Organizational governance policies for AWS accounts.

**Available Policies:**
- 🚫 Block RDS BYOL licensing
- 🔒 Enforce security standards
- 💰 Cost control measures

## 🎯 Architecture Patterns

### Multi-Tier Web Application
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Internet      │    │   Application   │    │   Database      │
│   Gateway       │───▶│   Load Balancer │───▶│   Layer         │
│                 │    │   (ALB)         │    │   (RDS)         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Public        │    │   Private       │    │   Database      │
│   Subnets       │    │   Subnets       │    │   Subnets       │
│                 │    │   (ECS Fargate) │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Serverless Application
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API Gateway   │───▶│   Lambda        │───▶│   RDS Proxy     │
│                 │    │   Function      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CloudFront    │    │   CloudWatch    │    │   RDS           │
│   Distribution  │    │   Logs          │    │   Database      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🛠️ Quick Start

### Prerequisites
- 🔧 Terraform >= 1.0
- ☁️ AWS CLI configured
- 🔑 Appropriate AWS permissions

### 1. Clone the Repository
```bash
git clone <repository-url>
cd AWS-Terraform-Playground
```

### 2. Choose Your Module
Navigate to the desired module directory:
```bash
cd Terrafrom-AWS-Prasanth/terraform-aws-ecs-fargate  # For ECS Fargate
cd Terrafrom-AWS-Prasanth/terraform-aws-lambda      # For Lambda
cd Terrafrom-AWS-Prasanth/terraform-aws-rds         # For RDS
```

### 3. Review Examples
Each module includes comprehensive examples:
```bash
ls examples/  # View available example configurations
```

### 4. Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply
```

## 📖 Documentation

- 📋 **[INDEX.md](INDEX.md)** - Detailed navigation and component guide
- 🔐 **[SCP Policies](aws-scp-policys/README.md)** - Service Control Policy documentation
- 🐳 **[ECS Fargate](Terrafrom-AWS-Prasanth/terraform-aws-ecs-fargate/README.md)** - Container orchestration
- ⚡ **[Lambda](Terrafrom-AWS-Prasanth/terraform-aws-lambda/README.md)** - Serverless functions
- 🗄️ **[RDS](Terrafrom-AWS-Prasanth/terraform-aws-rds/)** - Database solutions

## 🏷️ Examples by Use Case

| Use Case | Components | Example Path |
|----------|------------|--------------|
| 🌐 Web Application | ECS + RDS + ALB | `terraform-aws-ecs-fargate/examples/complete/` |
| ⚡ Serverless API | Lambda + RDS | `terraform-aws-lambda/examples/complete/` |
| 🗄️ Database Migration | RDS + Snapshots | `terraform-aws-rds/examples/postgres-db-instance/` |
| 🔄 Multi-Region Setup | RDS Cross-Region | `terraform-aws-rds/examples/cross-region-snapshot-copy/` |

## 🔒 Security & Governance

### Service Control Policies
- **Block BYOL Licensing**: Prevents unauthorized license models
- **Compliance**: Ensures organizational standards
- **Cost Control**: Manages resource usage

### Security Best Practices
- 🔐 Encryption at rest and in transit
- 🛡️ IAM least privilege access
- 🌐 VPC isolation
- 📊 CloudWatch monitoring
- 🔍 AWS CloudTrail logging

## 🤝 Contributing

1. 🍴 Fork the repository
2. 🌿 Create a feature branch
3. ✅ Add tests and documentation
4. 📝 Submit a pull request

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🏷️ Tags

`terraform` `aws` `infrastructure-as-code` `ecs` `fargate` `lambda` `rds` `scp` `devops` `cloud` `automation`
