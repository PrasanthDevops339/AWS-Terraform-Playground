# Automated Cross-Region RDS Backup using Lambda and EventBridge

This Terraform configuration provides an automated, serverless solution for cross-region RDS snapshot backup that works with **ANY RDS engine type** and option groups, including Oracle with custom options that cause AWS Backup to fail.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   EventBridge   │ -> │  Lambda Function │ -> │   RDS Primary   │
│   (Scheduler)   │    │  (Backup Logic)  │    │    (Source)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ RDS Secondary   │
                       │   (Snapshots)   │
                       └─────────────────┘
```

## ✨ Key Features

- **🔄 Universal Compatibility**: Works with ANY RDS engine (Oracle EE/SE2, MySQL, PostgreSQL, etc.)
- **🎯 Option Group Support**: Handles custom option groups that break AWS Backup
- **⚡ Serverless**: Event-driven Lambda execution - no infrastructure to manage
- **🔐 Security**: KMS encryption for cross-region snapshots
- **🧹 Lifecycle Management**: Automatic cleanup of old snapshots
- **📊 Monitoring**: CloudWatch logs and error handling
- **💰 Cost Optimized**: Pay-per-execution model

## 🚀 What This Solution Does

1. **Automated Scheduling**: EventBridge triggers Lambda on your schedule (default: every 6 hours)
2. **Smart Snapshot Creation**: Creates snapshots of your RDS instance
3. **Cross-Region Copy**: Copies snapshots to secondary region with proper encryption
4. **Option Group Handling**: Automatically uses compatible option groups in secondary region
5. **Cleanup Management**: Removes old snapshots based on retention policy
6. **Error Handling**: Comprehensive logging and error recovery

## 📋 Requirements

- RDS instance in primary region (any engine type)
- VPCs in both primary and secondary regions
- AWS Lambda execution permissions
- KMS keys for encryption in both regions

## 🔧 Configuration

### Key Variables

```hcl
# Backup scheduling
lambda_schedule = "rate(6 hours)"  # or "cron(0 2 * * ? *)"

# Retention policy
snapshot_retention_days = 7

# Lambda timeout
lambda_timeout = 300
```

### Supported Engines

- ✅ Oracle Enterprise Edition (with custom options)
- ✅ Oracle Standard Edition 2
- ✅ MySQL
- ✅ PostgreSQL
- ✅ MariaDB
- ✅ SQL Server
- ✅ Any other RDS engine

## 🏃‍♂️ Deployment

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

## 🎛️ How It Works

### 1. **Primary Region Setup**
- Creates Oracle SE2 RDS instance (cost-optimized)
- Sets up KMS encryption
- Configures security groups
- Deploys custom option/parameter groups

### 2. **Secondary Region Preparation**
- Creates compatible option groups (matches primary)
- Sets up parameter groups (identical configuration)
- Configures KMS keys for cross-region encryption
- **NO RDS instance created** (as requested)

### 3. **Lambda Automation**
- Monitors RDS instance in primary region
- Creates snapshots automatically
- Handles cross-region copying with proper option group mapping
- Manages snapshot lifecycle and cleanup

### 4. **EventBridge Scheduling**
- Triggers Lambda function on schedule
- Passes RDS instance details to Lambda
- Provides reliable, managed scheduling

## 📊 Monitoring

- **CloudWatch Logs**: `/aws/lambda/rds-backup-lambda-*`
- **Metrics**: Lambda execution metrics and RDS snapshot status
- **Alerts**: Can be configured for backup failures

## 💡 Benefits Over Manual Approach

| Manual Snapshots | Lambda Automation |
|-----------------|-------------------|
| ❌ Manual intervention required | ✅ Fully automated |
| ❌ Limited to specific engines | ✅ Works with ANY RDS engine |
| ❌ Complex option group handling | ✅ Automatic option group mapping |
| ❌ No lifecycle management | ✅ Automatic cleanup |
| ❌ Fixed infrastructure costs | ✅ Pay-per-execution |
| ❌ Manual scheduling | ✅ Flexible EventBridge scheduling |

## 🔄 Disaster Recovery

When you need to restore from backup snapshots:

1. Snapshots are available in secondary region
2. Option/parameter groups are pre-created and compatible
3. Simply restore RDS instance from snapshot
4. Use existing secondary region option/parameter groups

## 🏷️ Cost Optimization

- **Lambda**: Pay only when backups run
- **Storage**: Intelligent snapshot lifecycle management
- **Instance**: Cost-optimized Oracle SE2 with minimal resources
- **Scheduling**: Flexible backup frequency

## 🔒 Security Features

- KMS encryption for all snapshots
- Cross-region key policies
- IAM least privilege access
- VPC isolation
- CloudWatch audit logging

This solution provides enterprise-grade automated backup capabilities while remaining cost-effective and maintenance-free! 🎉
