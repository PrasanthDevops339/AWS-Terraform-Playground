# 📋 AWS Terraform Playground - Complete Index

A comprehensive navigation guide for all components, modules, and configurations in this repository.

## 🗂️ Directory Structure Overview

```
AWS-Terraform-Playground/
├── 📄 README.md                          # Main documentation
├── 📄 INDEX.md                           # This navigation file
├── 🔐 aws-scp-policys/                   # AWS Service Control Policies
│   ├── 📄 README.md                      # SCP documentation & usage
│   └── 📝 block-rds-byol.json           # Block RDS BYOL policy
└── ⚙️ Terrafrom-AWS-Prasanth/            # Core Terraform modules
    ├── 🐳 terraform-aws-ecs-fargate/     # Container orchestration
    │   ├── 📄 README.md                  # ECS module documentation
    │   ├── ⚙️ ecs-cluster.tf             # ECS cluster configuration
    │   ├── ⚙️ ecs-service.tf             # ECS service configuration
    │   ├── ⚙️ task-definition.tf         # Task definition setup
    │   ├── ⚙️ service-autoscaling.tf     # Auto-scaling configuration
    │   ├── 📊 variables.tf               # Input variables
    │   ├── 📊 output.tf                  # Output values
    │   ├── 📊 data.tf                    # Data sources
    │   ├── 📊 versions.tf                # Provider versions
    │   ├── 🔄 .gitlab-ci.yml             # CI/CD pipeline
    │   ├── 📋 CHANGELOG.md               # Version history
    │   └── 📁 examples/                  # Usage examples
    │       ├── 📁 complete/              # Full implementation
    │       └── 📁 simple/                # Basic setup
    ├── ⚡ terraform-aws-lambda/          # Serverless functions
    │   ├── 📄 README.md                  # Lambda module documentation
    │   ├── ⚙️ main.tf                    # Main Lambda configuration
    │   ├── ⚙️ lambda-package.tf          # Package management
    │   ├── ⚙️ test_events.tf             # Test event configuration
    │   ├── 📊 variables.tf               # Input variables
    │   ├── 📊 outputs.tf                 # Output values
    │   ├── 📊 data.tf                    # Data sources
    │   ├── 📊 versions.tf                # Provider versions
    │   ├── 🔄 .gitlab-ci.yml             # CI/CD pipeline
    │   ├── 📋 CHANGELOG.md               # Version history
    │   ├── 📁 templates/                 # Lambda templates
    │   └── 📁 examples/                  # Usage examples
    │       └── 📁 complete/              # Full implementation
    ├── 📁 terraform-aws-lambda-old/      # Legacy Lambda module
    └── 🗄️ terraform-aws-rds/             # Database solutions
        ├── ⚙️ main.tf                    # Main RDS configuration
        ├── ⚙️ cloudwatch.tf              # Monitoring setup
        ├── ⚙️ option-group.tf            # RDS option groups
        ├── ⚙️ parameter-group.tf         # RDS parameter groups
        ├── ⚙️ subnet-group.tf            # Database subnet groups
        ├── ⚙️ password.tf                # Password management
        ├── ⚙️ provider.tf                # Provider configuration
        ├── ⚙️ locals.tf                  # Local values
        ├── 📊 variables.tf               # Input variables
        ├── 📊 outputs.tf                 # Output values
        ├── 📊 data.tf                    # Data sources
        └── 📁 examples/                  # Usage examples
            ├── 📁 postgres-db-instance/  # PostgreSQL setup
            ├── 📁 mysql-db-instance/     # MySQL setup
            ├── 📁 oracle-db-instance/    # Oracle setup
            ├── 📁 mssql-db-instance/     # SQL Server setup
            ├── 📁 replica-postgres-instance/ # Read replica
            ├── 📁 cross-region-snapshot-copy/ # Cross-region backup
            └── 📁 cross-region-manual-snapshot-copy/ # Manual backup
```

## 🔐 AWS Service Control Policies (SCPs)

### 📁 aws-scp-policys/

Service Control Policies for organizational governance and compliance.

#### 📄 Available Policies

| Policy | File | Purpose | Affected Services |
|--------|------|---------|-------------------|
| 🚫 Block RDS BYOL | `block-rds-byol.json` | Prevents BYOL license models | Amazon RDS |

#### 🔧 Policy Details

**Block RDS BYOL Policy:**
- **Actions Blocked:**
  - `rds:CreateDBInstance`
  - `rds:CreateDBInstanceReadReplica`
  - `rds:RestoreDBInstanceFromDBSnapshot`
  - `rds:RestoreDBInstanceFromS3`
  - `rds:RestoreDBInstanceToPointInTime`
  - `rds:ModifyDBInstance`
- **Database Engines:** Oracle, SQL Server
- **License Model:** Bring-Your-Own-License (BYOL)

## ⚙️ Terraform Modules

### 🐳 ECS Fargate Module

**Location:** `Terrafrom-AWS-Prasanth/terraform-aws-ecs-fargate/`

#### 📋 Core Components

| File | Purpose | Description |
|------|---------|-------------|
| `ecs-cluster.tf` | Cluster Setup | ECS cluster configuration |
| `ecs-service.tf` | Service Management | ECS service and networking |
| `task-definition.tf` | Task Configuration | Container task definitions |
| `service-autoscaling.tf` | Scaling Logic | Auto-scaling policies |

#### 🎯 Key Features

- ✅ **Application Load Balancer Integration**
- ✅ **Auto-scaling with CloudWatch metrics**
- ✅ **VPC networking and security groups**
- ✅ **ECS Exec support for debugging**
- ✅ **Multiple container support**
- ✅ **Health check configuration**

#### 📊 Variables & Outputs

**Key Variables:**
- `cluster_name` - ECS cluster identifier
- `vpc_id` - VPC for deployment
- `target_groups` - Load balancer target groups
- `container_config` - Container specifications

**Key Outputs:**
- ECS cluster ARN
- Service ARNs
- Task definition ARNs

#### 📁 Examples Available

1. **Complete Example** (`examples/complete/`)
   - Full multi-container setup
   - Load balancer integration
   - Auto-scaling configuration

2. **Simple Example** (`examples/simple/`)
   - Basic single-container deployment
   - Minimal configuration

### ⚡ Lambda Function Module

**Location:** `Terrafrom-AWS-Prasanth/terraform-aws-lambda/`

#### 📋 Core Components

| File | Purpose | Description |
|------|---------|-------------|
| `main.tf` | Lambda Function | Core Lambda configuration |
| `lambda-package.tf` | Package Management | Zip file and S3 upload |
| `test_events.tf` | Testing | Test event configuration |

#### 🎯 Key Features

- ✅ **Automatic packaging and deployment**
- ✅ **S3 upload support**
- ✅ **VPC configuration**
- ✅ **Environment variables**
- ✅ **Event source mapping**
- ✅ **Dead letter queues**
- ✅ **Layers support**
- ✅ **Container image support**

#### 📊 Critical Variables

**Function Configuration:**
- `lambda_name` - Function identifier
- `lambda_role_arn` - IAM role ARN
- `runtime` - Runtime environment
- `handler` - Entry point
- `memory_size` - Memory allocation
- `timeout` - Execution timeout

**Package Configuration:**
- `lambda_script` - Function code
- `lambda_script_dir` - Source directory
- `upload_to_s3` - S3 upload flag
- `package_type` - Zip or Image

**Advanced Configuration:**
- `vpc_config` - VPC networking
- `environment` - Environment variables
- `layers` - Lambda layers
- `event_source_mapping` - Event triggers

#### 📁 Examples Available

1. **Complete Example** (`examples/complete/`)
   - Full feature demonstration
   - VPC configuration
   - Event source mapping

### 🗄️ RDS Database Module

**Location:** `Terrafrom-AWS-Prasanth/terraform-aws-rds/`

#### 📋 Core Components

| File | Purpose | Description |
|------|---------|-------------|
| `main.tf` | RDS Instance | Core database configuration |
| `subnet-group.tf` | Networking | Database subnet groups |
| `parameter-group.tf` | Performance | Database parameters |
| `option-group.tf` | Features | Database options |
| `cloudwatch.tf` | Monitoring | CloudWatch integration |
| `password.tf` | Security | Password management |

#### 🎯 Key Features

- ✅ **Multi-engine support** (PostgreSQL, MySQL, Oracle, SQL Server)
- ✅ **High availability with Multi-AZ**
- ✅ **Read replicas**
- ✅ **Cross-region backup**
- ✅ **Encryption at rest**
- ✅ **Performance Insights**
- ✅ **Automated backups**
- ✅ **Parameter group customization**

#### 📊 Essential Variables

**Database Configuration:**
- `identifier` - Database identifier
- `engine` - Database engine
- `engine_version` - Engine version
- `instance_class` - Instance type
- `allocated_storage` - Storage size

**Security & Networking:**
- `vpc_security_group_ids` - Security groups
- `db_subnet_group_name` - Subnet group
- `kms_key_id` - Encryption key

**Backup & Maintenance:**
- `backup_retention_period` - Backup retention
- `maintenance_window` - Maintenance timing
- `backup_window` - Backup timing

#### 📁 Examples by Database Engine

| Engine | Example Directory | Features |
|--------|-------------------|----------|
| 🐘 PostgreSQL | `postgres-db-instance/` | Standard PostgreSQL setup |
| 🐬 MySQL | `mysql-db-instance/` | Standard MySQL setup |
| 🔶 Oracle | `oracle-db-instance/` | Oracle Database setup |
| 🏢 SQL Server | `mssql-db-instance/` | SQL Server setup |
| 📖 Read Replica | `replica-postgres-instance/` | PostgreSQL read replica |
| 🔄 Cross-Region | `cross-region-snapshot-copy/` | Automated cross-region backup |
| 🔄 Manual Backup | `cross-region-manual-snapshot-copy/` | Manual cross-region backup |

## 🚀 Quick Navigation

### By Use Case

#### 🌐 Web Application Development
1. **Start here:** [ECS Fargate Module](#-ecs-fargate-module)
2. **Database:** [RDS Module](#️-rds-database-module)
3. **Example:** `terraform-aws-ecs-fargate/examples/complete/`

#### ⚡ Serverless Development
1. **Start here:** [Lambda Module](#-lambda-function-module)
2. **Database:** [RDS Module](#️-rds-database-module)
3. **Example:** `terraform-aws-lambda/examples/complete/`

#### 🔒 Governance & Compliance
1. **Start here:** [SCP Policies](#-aws-service-control-policies-scps)
2. **Documentation:** `aws-scp-policys/README.md`

#### 🗄️ Database Migration
1. **Start here:** [RDS Module](#️-rds-database-module)
2. **Examples:** Choose appropriate engine example
3. **Cross-region:** Use cross-region examples

### By Technology

| Technology | Module | Documentation | Examples |
|------------|--------|---------------|----------|
| 🐳 Docker/Containers | ECS Fargate | `terraform-aws-ecs-fargate/README.md` | `examples/complete/` |
| ⚡ Serverless | Lambda | `terraform-aws-lambda/README.md` | `examples/complete/` |
| 🗄️ Databases | RDS | View examples | Multiple engine examples |
| 🔐 Governance | SCP | `aws-scp-policys/README.md` | Policy files |

## 🔧 Development Workflow

### 1. Module Selection
```bash
# Navigate to desired module
cd Terrafrom-AWS-Prasanth/terraform-aws-[module-name]/
```

### 2. Example Review
```bash
# Explore examples
ls examples/
cd examples/complete/  # or simple/
```

### 3. Customization
```bash
# Copy example as starting point
cp -r examples/complete/ my-implementation/
cd my-implementation/
```

### 4. Configuration
```bash
# Edit variables
vim terraform.tfvars
```

### 5. Deployment
```bash
terraform init
terraform plan
terraform apply
```

## 📚 Documentation Standards

Each module follows consistent documentation patterns:

### 📄 README.md Structure
1. **Module Overview** - Purpose and capabilities
2. **Architecture Diagrams** - Visual representations
3. **Usage Examples** - Code samples
4. **Variables Reference** - Input parameters
5. **Outputs Reference** - Return values
6. **Advanced Configuration** - Complex scenarios

### 📊 Variable Documentation
- **Type** - Data type
- **Description** - Purpose and usage
- **Default** - Default value
- **Required/Optional** - Necessity flag
- **Validation** - Input constraints

### 📁 Example Structure
- **Simple** - Basic implementation
- **Complete** - Full-featured implementation
- **Specific Use Cases** - Targeted scenarios

## 🏷️ Tags and Labels

### Module Categories
- `container` - Container orchestration
- `serverless` - Serverless computing
- `database` - Data storage solutions
- `governance` - Organizational policies

### Complexity Levels
- 🟢 **Beginner** - Simple examples
- 🟡 **Intermediate** - Standard implementations
- 🔴 **Advanced** - Complex configurations

### Infrastructure Types
- 🏗️ **Core Infrastructure** - Foundational components
- 🔧 **Application Infrastructure** - Application-specific
- 🔐 **Security Infrastructure** - Security-focused
- 📊 **Monitoring Infrastructure** - Observability

## 🤝 Contributing Guidelines

### Adding New Modules
1. Create module directory structure
2. Follow naming conventions
3. Include comprehensive examples
4. Document all variables and outputs
5. Update this INDEX.md

### Updating Existing Modules
1. Maintain backward compatibility
2. Update CHANGELOG.md
3. Update documentation
4. Test all examples

### Documentation Updates
1. Keep INDEX.md current
2. Update README files
3. Maintain architectural diagrams
4. Verify all links work

---

## 📞 Support and Resources

- 📖 **Main Documentation:** [README.md](README.md)
- 🔐 **SCP Policies:** [aws-scp-policys/README.md](aws-scp-policys/README.md)
- 🐳 **ECS Fargate:** [terraform-aws-ecs-fargate/README.md](Terrafrom-AWS-Prasanth/terraform-aws-ecs-fargate/README.md)
- ⚡ **Lambda Functions:** [terraform-aws-lambda/README.md](Terrafrom-AWS-Prasanth/terraform-aws-lambda/README.md)

---

*Last Updated: October 2025*
