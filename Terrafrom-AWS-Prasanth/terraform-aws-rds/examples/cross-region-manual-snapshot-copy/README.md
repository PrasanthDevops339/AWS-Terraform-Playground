# Cross-Region Manual Snapshot Copy Example

This example demonstrates the **manual snapshot copy approach** for cross-region RDS backup when AWS Backup limitations prevent automated bac## Complete Restoration Architecture

This example now provides **complete restoration infrastructure** in the secondary region:

```hcl
# 🔧 Secondary Region - Complete Infrastructure
resource "aws_db_parameter_group" "secondary_parameter_group" {
  # Identical Oracle performance settings
  parameter {
    name  = "shared_pool_size"
    value = "134217728"
  }
  parameter {
    name  = "db_cache_size" 
    value = "268435456"
  }
}

module "secondary_security_group" {
  # Identical network access rules
  ingress_rules = [{
    from_port = 1521
    to_port   = 1521
    cidr_ipv4 = data.aws_vpc.secondary.cidr_block
  }]
}

# 🚀 Disaster Recovery - Complete Configuration
module "oracle_disaster_recovery" {
  snapshot_identifier       = aws_db_snapshot.secondary_backup_copy.id
  parameter_group_name      = aws_db_parameter_group.secondary_parameter_group.name
  db_option_group_name      = aws_db_option_group.secondary_option_group.name
  vpc_security_group_ids    = [module.secondary_security_group.security_group_id]
}
```

## Important Notes

### Complexity Considerations

1. **Complete Secondary Infrastructure**: Parameter groups, security groups, and option groups in secondary region
2. **Option Group Compatibility**: Target region option group must have identical options as source
3. **Engine Version Matching**: Both source and target must use the same Oracle engine version
4. **Parameter Group Synchronization**: ✅ **Now Included** - Identical parameter groups ensure consistent performance
5. **Security Group Matching**: ✅ **Now Included** - Proper network access for restoration scenarios  
6. **Manual Orchestration**: Requires careful coordination of snapshot creation and copyingation. This approach is designed for edge cases where custom option groups with persistent options (like STATSPACK) prevent the use of automated backup replication.

> **💡 When to Use This Approach**: This manual method works for **both Multi-AZ DB instances and Multi-AZ DB clusters**. If you have Multi-AZ DB clusters, this is one of your main options since Cross-Region Automated Backups (CRAB) doesn't support clusters.

## When to Use This Approach

Use this complex manual approach **when**:
- Your RDS instance has custom option groups with persistent/permanent options
- You're using **Multi-AZ DB clusters** (MySQL/PostgreSQL clusters where CRAB doesn't work)
- AWS automated backup replication fails due to option group incompatibilities
- You need fine-grained control over snapshot timing and retention
- Standard automated backup replication doesn't meet specific compliance requirements

## Problem Statement

AWS Backup and automated backup replication can fail when:
- RDS instances have custom option groups with persistent options (e.g., Oracle STATSPACK, Timezone)
- Cross-region compatibility issues with specific option group configurations
- Complex option group dependencies that require manual handling

## Solution Overview

This example implements a **manual orchestration approach** using:

1. **Primary RDS Instance**: Oracle Enterprise Edition with custom option groups
2. **Secondary Region Preparation**: Compatible option groups in target region
3. **Manual Snapshot Creation**: Multiple snapshots simulating hourly backups
4. **Cross-Region Copy**: Manual snapshot copying with option group compatibility
5. **Optional Restoration**: Restore capability in secondary region

## Architecture

Complete cross-region disaster recovery infrastructure with manual snapshot orchestration:

```
Primary Region (us-east-2)                    Secondary Region (us-east-1)
┌─────────────────────────────┐              ┌─────────────────────────────┐
│  🏢 Production Environment  │              │  🚨 Disaster Recovery Env   │
│                             │              │                             │
│  📊 Oracle RDS Instance     │              │  🔧 Complete Infrastructure │
│  ├─ Custom Option Groups    │              │  ├─ Parameter Groups        │
│  │  ├─ STATSPACK           │              │  │  ├─ shared_pool_size     │
│  │  └─ Timezone (Eastern)  │              │  │  └─ db_cache_size        │
│  ├─ Parameter Groups        │              │  ├─ Security Groups         │
│  │  ├─ shared_pool_size     │              │  │  └─ Oracle Port 1521     │
│  │  └─ db_cache_size        │              │  ├─ Option Groups           │
│  ├─ Security Groups         │              │  │  ├─ STATSPACK           │
│  │  └─ Oracle Port 1521     │              │  │  └─ Timezone (Eastern)  │
│  ├─ KMS Encryption          │              │  ├─ KMS Encryption          │
│  └─ SNS Notifications       │              │  └─ SNS Notifications       │
└─────────────────────────────┘              └─────────────────────────────┘
              │                                              │
              ▼                                              ▼
┌─────────────────────────────┐              ┌─────────────────────────────┐
│  📸 Manual Snapshots        │   ════════▶  │  📦 Cross-Region Copies     │
│  ├─ hourly_snapshots[0-2]   │              │  ├─ secondary_backup_copy   │
│  ├─ primary_manual          │              │  ├─ secondary_backup_copies │
│  └─ Auto-tagged & Encrypted │              │  └─ Compatible Option Groups│
└─────────────────────────────┘              └─────────────────────────────┘
                                                            │
                                                            ▼
                                             ┌─────────────────────────────┐
                                             │  🔄 Disaster Recovery       │
                                             │  ├─ oracle_disaster_recovery │
                                             │  ├─ Complete Configuration   │
                                             │  ├─ Parameter Groups         │
                                             │  ├─ Security Groups          │
                                             │  └─ Option Groups            │
                                             └─────────────────────────────┘
```

### Key Architecture Benefits:

- **🔄 Complete DR**: Full secondary region infrastructure for seamless restoration
- **🔐 Security**: KMS encryption, VPC isolation, least-privilege IAM
- **📊 Monitoring**: SNS notifications, CloudWatch logs, Performance Insights
- **⚡ Performance**: Optimized Oracle parameters in both regions
- **🎯 Compatibility**: Identical configurations across regions for reliable restoration

## Deployment

This example demonstrates a complete cross-region disaster recovery solution with automated snapshot orchestration and full secondary region infrastructure for seamless database restoration.

## Key Components

### 1. Primary Region Resources

- **Oracle RDS Instance**: With custom option groups (STATSPACK, Timezone) and parameter groups
- **Security Group**: Using `tfe.com/security-group/aws` module for database access
- **KMS Key**: Using `tfe.com/kms/aws` module for encryption
- **SNS Topic**: Using `tfe.com/sns/aws` module for RDS events

### 2. Secondary Region Infrastructure (New - Complete Restoration Capability)

- **Parameter Group**: `aws_db_parameter_group.secondary_parameter_group`
  - Identical Oracle performance settings: shared_pool_size, db_cache_size
  - Ensures restored databases maintain custom performance tuning
- **Security Group**: `module.secondary_security_group` 
  - Oracle port 1521 access from VPC CIDR
  - Proper network connectivity for disaster recovery scenarios
- **Option Group**: Compatible STATSPACK and Timezone options for snapshot restoration

### 2. Secondary Region Resources (Complete Restoration Infrastructure)

- **Parameter Group**: Identical custom Oracle settings (shared_pool_size, db_cache_size)
- **Security Group**: Matching network access rules for database connectivity
- **Option Group**: Compatible persistent options (STATSPACK, Timezone) for snapshot restoration
- **KMS Key**: Secondary region encryption key with cross-region access policies
- **SNS Topic**: Secondary region event notifications

### 3. Manual Snapshot and Cross-Region Copy Process

```hcl
# Step 1: Create multiple hourly snapshots
resource "aws_db_snapshot" "hourly_snapshots" {
  count = var.hourly_snapshots_count
  
  db_instance_identifier = module.oracle_primary.db_instance_identifier
  db_snapshot_identifier = "${local.name}-hourly-${count.index + 1}-${random_string.module_id.result}"
}

# Step 2: Cross-region copy with option group compatibility
resource "aws_db_snapshot" "secondary_backup_copy" {
  provider = aws.secondary
  
  source_db_snapshot_identifier = aws_db_snapshot.hourly_snapshots[0].db_snapshot_arn
  target_db_snapshot_identifier = "secondary-backup-copy"
  
  # CRITICAL: Specify target option group for compatibility
  option_group_name = aws_db_option_group.secondary_option_group.name
}

# Step 3: Copy additional hourly snapshots
resource "aws_db_snapshot" "secondary_backup_copies" {
  provider = aws.secondary
  count    = length(aws_db_snapshot.hourly_snapshots) - 1
  
  source_db_snapshot_identifier = aws_db_snapshot.hourly_snapshots[count.index + 1].db_snapshot_arn
  target_db_snapshot_identifier = "secondary-backup-${count.index + 2}"
  
  option_group_name = aws_db_option_group.secondary_option_group.name
}
```

## Important Notes

### Complexity Considerations

1. **Multiple Resources**: Requires preparation instances, manual snapshots, and copy resources
2. **Option Group Compatibility**: Target region option group must have identical options as source
3. **Engine Version Matching**: Both source and target must use the same Oracle engine version
4. **Parameter Groups**: Parameter groups should also match for full compatibility
5. **Higher Cost**: Creates multiple RDS instances and snapshots for demonstration
6. **Manual Orchestration**: Requires careful coordination of snapshot creation and copying

### Maintenance Requirements

1. **Snapshot Cleanup**: Manual cleanup of old snapshots required
2. **Option Group Sync**: Keep option groups synchronized between regions
3. **Monitoring**: Monitor snapshot creation and copy operations
4. **Error Handling**: Handle failures in snapshot creation or copying

## Cost Considerations

This approach has higher costs due to:

1. **Multiple RDS Instances**: Primary instance + preparation instance in secondary region
2. **Manual Snapshots**: Storage costs for multiple manual snapshots
3. **Cross-Region Transfer**: Data transfer costs for snapshot copying
4. **Operational Overhead**: Manual management and monitoring required

### Production Recommendations

For production use with this approach:

1. **Automated Scheduling**: Use EventBridge + Lambda for true hourly snapshots
2. **Retention Policies**: Implement automated cleanup for old snapshots
3. **Monitoring**: Set up CloudWatch alarms for snapshot operations
4. **Cost Optimization**: Consider snapshot lifecycle policies

## Troubleshooting

### Common Issues

1. **Option Group Mismatch**: Ensure target option group has identical options as source
2. **Engine Version Mismatch**: Verify exact engine versions match between regions
3. **IAM Permissions**: Ensure cross-region snapshot copy permissions are granted
4. **KMS Key Access**: Verify KMS key policies allow cross-region operations
5. **Snapshot State**: Source snapshots must be in 'available' state before copying

### Validation

The example includes comprehensive outputs that confirm:
- ✅ Primary RDS created with custom option groups
- ✅ Secondary compatible option group exists
- ✅ Cross-region snapshot copy completed successfully
- ✅ All manual orchestration components working

### Quick Verification Commands

After deployment, verify the manual snapshot process is working:

```bash
# Check manual snapshots in primary region (us-east-2)
aws rds describe-db-snapshots --region us-east-2 \
  --query 'DBSnapshots[?contains(DBSnapshotIdentifier, `oracle-cross-region`)].{Identifier:DBSnapshotIdentifier,Status:Status,Engine:Engine,Created:SnapshotCreateTime}' \
  --output table

# Check cross-region copied snapshots in secondary region (us-east-1)
aws rds describe-db-snapshots --region us-east-1 \
  --query 'DBSnapshots[?contains(DBSnapshotIdentifier, `secondary-backup`)].{Identifier:DBSnapshotIdentifier,Status:Status,SourceRegion:SourceRegion,OptionGroup:OptionGroupName}' \
  --output table

# Check option groups in both regions
aws rds describe-option-groups --region us-east-2 --query 'OptionGroupsList[?contains(OptionGroupName, `oracle-cross-region`)].{Name:OptionGroupName,Engine:EngineName,Options:Options[].OptionName}' --output table
aws rds describe-option-groups --region us-east-1 --query 'OptionGroupsList[?contains(OptionGroupName, `oracle-cross-region`)].{Name:OptionGroupName,Engine:EngineName,Options:Options[].OptionName}' --output table
```

Expected output should show:
- ✅ Manual snapshots created in primary region with "available" status
- ✅ Cross-region copies in secondary region with source region "us-east-2"
- ✅ Compatible option groups in both regions with matching options

## Alternative: Simple Automated Approach

## Decision Matrix: Which Approach to Use?

| Your Setup | Recommended Solution | Reason |
|-------------|---------------------|---------|
| **Multi-AZ DB Instance** + No custom option groups | [Simple CRAB](../cross-region-snapshot-copy/) | ✅ AWS managed, simple |
| **Multi-AZ DB Instance** + Custom option groups | **This manual approach** | ⚠️ CRAB may fail with persistent options |
| **Multi-AZ DB Cluster** (MySQL/PostgreSQL) | **This manual approach** or AWS Backup | ❌ CRAB doesn't support clusters |
| **Oracle SE2/EE** or **SQL Server** | [Simple CRAB](../cross-region-snapshot-copy/) | ✅ Only have Multi-AZ instances, not clusters |

### Before Using This Complex Approach

**Try the simple automated backup replication first** in the main `cross-region-snapshot-copy` example:

```hcl
resource "aws_db_instance_automated_backups_replication" "cross_region" {
  provider = aws.secondary
  
  source_db_instance_arn = module.oracle_primary.db_instance_arn
  kms_key_id            = module.secondary_kms.key_arn
}
```

**Use this complex manual approach when**:
- The simple CRAB approach fails due to option group limitations
- You have Multi-AZ DB clusters (where CRAB isn't supported)
- You need specific snapshot timing or retention controls

## Cleanup

```bash
# Destroy all resources (will take longer due to multiple instances)
terraform destroy -var="account_id=123456789012"
```

**Warning**: This will destroy multiple RDS instances across two regions. Ensure you have backups of any important data before cleanup.