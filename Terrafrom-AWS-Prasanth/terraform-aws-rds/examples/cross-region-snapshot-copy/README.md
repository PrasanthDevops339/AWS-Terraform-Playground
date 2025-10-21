# Cross-Region RDS Automated Backup Replication Example

This example demonstrates how to implement cross-region disaster recovery for RDS instances using AWS's native automated backup replication service. This is the **recommended approach** for most RDS cross-region backup scenarios.

> **⚠️ Multi-AZ Compatibility Note**: Cross-Region Automated Backups (CRAB) works with **Multi-AZ DB instances** (classic) but **NOT** with **Multi-AZ DB clusters** (newer architecture). See [compatibility guide](#multi-az-compatibility) below.

> **Note**: For edge cases where custom option groups prevent automated backup replication, see the [`cross-region-manual-snapshot-copy`](../cross-region-manual-snapshot-copy/) example which demonstrates manual snapshot copying approach.

## Quick Start

```bash
# 1. Clone and navigate
cd terraform-aws-rds/examples/cross-region-snapshot-copy

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS account ID

# 3. Deploy
terraform init && terraform apply

# 4. Verify replication (after ~10 minutes)
aws rds describe-db-instance-automated-backups --region us-east-1 --output table
```

## Problem Statement

Organizations need reliable cross-region backup strategies for disaster recovery. While AWS Backup provides excellent backup services, there are scenarios where direct automated backup replication using RDS native services is preferred for simplicity and cost-effectiveness.

## Solution Overview

This example implements **automated backup replication** using `aws_db_instance_automated_backups_replication`:

1. **Primary RDS Instance**: Oracle Enterprise Edition in us-east-2
2. **Automated Backup Replication**: Single AWS resource that handles all cross-region backup copying
3. **Cross-Region KMS**: Separate encryption keys for each region
4. **Point-in-Time Recovery**: Full PITR capability in both regions
5. **AWS Managed**: No manual snapshot management or complex orchestration required

## Remediation Changes Implemented

- ✅ Decreased `backup_retention_period` from 3 days to 1 day
- ✅ Removed `kms_key_automated_backup_replication` variable
- ✅ Removed secondary provider dependency for cross-region support
- ✅ Removed configuration aliases for provider configurations
- ✅ Removed provider argument from all data and resource blocks
- ✅ Removed `aws_db_instance_automated_backups_replication` resource

## Architecture

```
Primary Region (us-east-2)                Secondary Region (us-east-1)
┌─────────────────────────┐              ┌─────────────────────────┐
│ Oracle RDS Instance     │              │                         │
│ + Automated Backups     │──────────────│  AWS Managed Backup     │
│ + Point-in-Time Recovery│              │     Replication         │
│ + KMS Encryption        │              │  + KMS Encryption       │
└─────────────────────────┘              │  + Point-in-Time        │
           │                             │  + Cross-Region Copy    │
           ▼                             └─────────────────────────┘
  ┌───────────────────┐                              │
  │ Single Resource:  │                              ▼
  │ aws_db_instance_  │                    ┌─────────────────────┐
  │ automated_backups_│                    │ Restore Capability  │
  │ replication       │                    │ in Secondary Region │
  └───────────────────┘                    └─────────────────────┘
```

### Key Benefits

- **🚀 Simple**: Single Terraform resource handles everything
- **💰 Cost Effective**: No extra RDS instances or manual snapshots
- **🔒 Secure**: KMS encryption in both regions
- **⚡ Fast Recovery**: Point-in-time recovery available in secondary region
- **🛡️ AWS Managed**: No maintenance or manual intervention required

## Usage

### Prerequisites

1. AWS credentials configured for both primary and secondary regions
2. Access to `tfe.com` module registry for:
   - `tfe.com/security-group/aws`
   - `tfe.com/kms/aws`
   - `tfe.com/sns/aws`

### Deploy the Example

```bash
# Navigate to the example directory
cd terraform-aws-rds/examples/cross-region-snapshot-copy

# Copy and customize the example variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS account ID and desired settings

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Verify backup replication is working (after RDS instance is created)
aws rds describe-db-instance-automated-backups --region us-east-1 --query 'DBInstanceAutomatedBackups[?contains(DBInstanceArn, `oracle-cross-region`)].{DBInstanceArn:DBInstanceArn,Region:Region,Status:Status}' --output table
```

### Configuration

Use the provided example variables file:

```bash
# Copy the example and customize
cp terraform.tfvars.example terraform.tfvars
```

**Required**: Update `account_id` in `terraform.tfvars`:

```hcl
account_id = "123456789012"  # Your AWS Account ID
```

### Optional Variables

```hcl
name                        = "oracle-cross-region"
source_region              = "us-east-1"
target_region              = "us-west-2"
engine_version             = "19.0.0.0.ru-2023-01.rur-2023-01.r1"
instance_class             = "db.t3.micro"
backup_retention_period    = 1
hourly_snapshots_count     = 3  # Number of hourly snapshots to create
enable_point_in_time_recovery = true

tags = {
  Owner       = "terraform-aws-rds"
  Environment = "dev"
  Purpose     = "cross-region-snapshot-copy-remediation"
}
```

## Key Components

### The Magic Resource (One Resource for Everything!)

```hcl
# This is ALL you need for cross-region backup replication!
resource "aws_db_instance_automated_backups_replication" "cross_region" {
  provider = aws.secondary
  
  source_db_instance_arn = module.oracle_primary.db_instance_arn
  kms_key_id            = module.secondary_kms.key_arn
  
  tags = {
    Name = "cross-region-backup-replication"
  }
}
```

**That's it!** AWS handles:
- ✅ Automated cross-region backup copying
- ✅ Point-in-time recovery in secondary region
- ✅ Backup retention management
- ✅ Encryption with secondary region KMS key
- ✅ No manual snapshots or complex orchestration needed

### Supporting Infrastructure

### 1. Primary Region Resources

- **Oracle RDS Instance**: Main database instance with automated backups enabled
- **Security Group**: Using `tfe.com/security-group/aws` module
- **KMS Key**: Using `tfe.com/kms/aws` module for encryption
- **SNS Topic**: Using `tfe.com/sns/aws` module for RDS events

### 2. Secondary Region Resources

- **KMS Key**: Secondary region encryption key for backup replication
- **AWS Managed Backup Replication**: No additional infrastructure needed!



## Important Notes

1. **Single Resource**: Only one `aws_db_instance_automated_backups_replication` resource needed
2. **AWS Managed**: AWS handles all the complexity of cross-region backup copying
3. **Point-in-Time Recovery**: Full PITR available in secondary region automatically
4. **Cost Effective**: No extra RDS instances or manual snapshots required
5. **Automatic Retention**: Respects the source instance backup retention period
6. **KMS Integration**: Uses secondary region KMS key for encryption
7. **No Lambda Required**: Pure AWS service, no custom functions needed
8. **Backup Window**: Respects the primary instance backup window for replication timing
9. **Network Independence**: Works across VPCs and regions without additional networking setup

## Cleanup

```bash
# Destroy all resources
terraform destroy -var="account_id=123456789012"
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure the AWS provider has permissions for:
   - `rds:CreateDBInstanceAutomatedBackupsReplication`
   - `rds:DeleteDBInstanceAutomatedBackupsReplication`
   - `kms:CreateGrant` (for cross-region KMS operations)

2. **KMS Key Access**: Verify KMS key policies allow cross-region operations
3. **Source Instance State**: Source RDS instance must have automated backups enabled
4. **Region Support**: Verify both regions support automated backup replication

### Validation

After deployment, verify:
- ✅ Primary RDS instance created in us-east-2
- ✅ Automated backup replication configured
- ✅ Secondary region KMS key accessible
- ✅ Backup retention settings applied correctly

### Monitoring

Use CloudWatch to monitor:
- RDS backup completion events
- Cross-region replication status
- Backup storage utilization in secondary region

### Quick Verification Commands

After deployment, verify the backup replication is working:

```bash
# Check automated backups in secondary region (us-east-1)
aws rds describe-db-instance-automated-backups --region us-east-1 \
  --query 'DBInstanceAutomatedBackups[?contains(DBInstanceArn, `oracle-cross-region`)].{DBInstanceArn:DBInstanceArn,Region:Region,Status:Status}' \
  --output table

# Alternative: Check all automated backups in secondary region
aws rds describe-db-instance-automated-backups --region us-east-1 --output table

# Check primary instance backup status
aws rds describe-db-instances --region us-east-2 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `oracle-cross-region`)].{Identifier:DBInstanceIdentifier,BackupRetention:BackupRetentionPeriod,BackupWindow:PreferredBackupWindow}' \
  --output table
```

Expected output should show:
- ✅ Primary instance with backup retention > 0
- ✅ Automated backups replicated to secondary region with "ACTIVE" status

## Multi-AZ Compatibility

### ✅ **Supported: Multi-AZ DB Instances (Classic)**

Cross-Region Automated Backups (CRAB) **works with**:
- **Oracle** (SE2, EE) - Multi-AZ instances
- **SQL Server** (Express, Web, Standard, Enterprise) - Multi-AZ instances  
- **PostgreSQL** - Multi-AZ instances
- **MySQL** - Multi-AZ instances

```hcl
# ✅ This works with CRAB
resource "aws_db_instance" "example" {
  engine          = "oracle-ee"
  multi_az        = true    # Classic Multi-AZ instance
  # ... other configuration
}

resource "aws_db_instance_automated_backups_replication" "example" {
  source_db_instance_arn = aws_db_instance.example.arn
  # ... works fine!
}
```

### ❌ **Not Supported: Multi-AZ DB Clusters**

Cross-Region Automated Backups (CRAB) **does NOT work with**:
- **MySQL** - Multi-AZ DB clusters (newer architecture)
- **PostgreSQL** - Multi-AZ DB clusters (newer architecture)

```hcl
# ❌ This does NOT work with CRAB
resource "aws_rds_cluster" "example" {
  engine      = "aurora-mysql"
  # OR regular MySQL/PostgreSQL in cluster mode
  # CRAB will fail!
}
```

### 🔄 **Alternative Solutions for Multi-AZ Clusters**

If you're using **Multi-AZ DB clusters**, use these instead:

| Solution | Use Case | Point-in-Time Recovery | Complexity |
|----------|----------|------------------------|------------|
| **AWS Backup with cross-region copy** | Snapshot-style DR | ❌ No cross-region PITR | Low |
| **Manual CopyDBSnapshot** | Custom snapshot handling | ❌ No cross-region PITR | Medium |
| **Engine-native replication** | Low RPO/RTO requirements | ✅ Yes (with replica) | High |

#### Option 1: AWS Backup (Recommended for Multi-AZ Clusters)

```hcl
resource "aws_backup_plan" "cross_region" {
  name = "cross-region-cluster-backup"
  
  rule {
    rule_name         = "cross_region_backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 2 * * ? *)"  # Daily at 2 AM
    
    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn
    }
    
    lifecycle {
      delete_after = 30
    }
  }
}
```

#### Option 2: Manual Snapshot Copy (See Complex Example)

Use the [`cross-region-manual-snapshot-copy`](../cross-region-manual-snapshot-copy/) example.

#### Option 3: Engine-Native Replication

Set up read replicas or logical replication in the target region.

### 🎯 **Quick Decision Guide**

**Are you using Multi-AZ DB clusters?**
- **No (Multi-AZ instances)** → ✅ Use this CRAB example
- **Yes (Multi-AZ clusters)** → ❌ Use AWS Backup or manual snapshot copy

**Not sure which Multi-AZ type you have?**

```bash
# Check if you have clusters (Multi-AZ clusters)
aws rds describe-db-clusters --query 'DBClusters[].{Identifier:DBClusterIdentifier,Engine:Engine,MultiAZ:MultiAZ}'

# Check if you have instances (Multi-AZ instances) 
aws rds describe-db-instances --query 'DBInstances[].{Identifier:DBInstanceIdentifier,Engine:Engine,MultiAZ:MultiAZ}'
```

### 📚 **Reference**

- **Multi-AZ DB Instance**: Traditional RDS instance with synchronous standby replica
- **Multi-AZ DB Cluster**: Newer architecture with multiple read replicas in different AZs
- **CRAB Support**: Only works with Multi-AZ DB **instances**, not DB **clusters**

## Cost Considerations

This example is cost-effective compared to manual snapshot approaches:

1. **Primary Instance**: Single Oracle RDS instance in us-east-2
2. **Secondary Infrastructure**: Only KMS key needed in us-east-1 (no secondary RDS instance)
3. **Backup Storage**: Standard automated backup storage costs in secondary region
4. **Data Transfer**: AWS manages cross-region backup replication efficiently
5. **No Manual Snapshots**: Eliminates costs associated with frequent manual snapshots

### Production Recommendations

1. **Backup Retention**: Set appropriate `backup_retention_period` (1-35 days)
2. **Backup Window**: Configure `backup_window` during low-traffic periods
3. **Monitoring**: Use CloudWatch to monitor backup replication status
4. **Cleanup**: AWS automatically manages backup retention and cleanup