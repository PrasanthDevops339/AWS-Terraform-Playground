"""
AWS Lambda Function for Automated RDS Cross-Region Backup

This Lambda function provides automated backup functionality for any RDS database engine
(Oracle, MySQL, PostgreSQL, SQL Server, etc.) with cross-region snapshot copying.

Key Features:
- Universal RDS engine support (works with any database type)
- Automated cross-region backup with KMS encryption
- Intelligent cleanup based on retention policies
- Proper error handling and logging
- Option group handling for Oracle databases
"""

import json
import boto3
import os
from datetime import datetime, timedelta
import logging

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================
# Set up structured logging for CloudWatch integration
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ============================================================================
# MAIN LAMBDA HANDLER FUNCTION
# ============================================================================
def lambda_handler(event, context):
    """
    🚀 MAIN ENTRY POINT - Automated RDS Cross-Region Backup Lambda Function
    
    This function orchestrates the complete backup workflow:
    1. 📋 Configuration Setup - Read environment variables and event data
    2. 📊 RDS Instance Discovery - Get database details and engine information
    3. 📸 Snapshot Creation - Create manual snapshot in primary region
    4. ⏳ Wait for Completion - Monitor snapshot creation progress
    5. 🔄 Cross-Region Copy - Copy snapshot to secondary region with encryption
    6. 🧹 Cleanup Process - Remove old snapshots based on retention policy
    7. ✅ Success Response - Return operation results
    
    Parameters:
        event (dict): Lambda event data containing db_instance_identifier
        context (object): Lambda context object with runtime information
    
    Returns:
        dict: Status response with operation results
    """
    
    try:
        # ====================================================================
        # STEP 1: CONFIGURATION SETUP
        # ====================================================================
        logger.info("=" * 60)
        logger.info("🚀 STARTING RDS CROSS-REGION BACKUP PROCESS")
        logger.info("=" * 60)
        
        # Read configuration from environment variables (set by Terraform)
        primary_region = os.environ.get('PRIMARY_REGION')
        secondary_region = os.environ.get('SECONDARY_REGION')
        retention_days = int(os.environ.get('RETENTION_DAYS', '7'))
        secondary_kms_key = os.environ.get('SECONDARY_KMS_KEY')
        secondary_option_group = os.environ.get('SECONDARY_OPTION_GROUP')
        
        logger.info(f"📍 Primary Region: {primary_region}")
        logger.info(f"📍 Secondary Region: {secondary_region}")
        logger.info(f"📅 Retention Policy: {retention_days} days")
        logger.info(f"🔐 KMS Key: {secondary_kms_key}")
        logger.info(f"⚙️  Option Group: {secondary_option_group}")
        
        # Extract database identifier from the incoming event
        db_instance_identifier = event.get('db_instance_identifier')
        if not db_instance_identifier:
            raise ValueError("❌ db_instance_identifier not provided in event")
        
        logger.info(f"🎯 Target RDS Instance: {db_instance_identifier}")
        logger.info("-" * 60)
        
        # ====================================================================
        # STEP 2: AWS CLIENT INITIALIZATION
        # ====================================================================
        logger.info("🔌 Initializing AWS RDS clients for both regions...")
        
        # Create RDS clients for primary and secondary regions
        # These clients will handle all RDS operations (snapshots, copying, etc.)
        primary_rds = boto3.client('rds', region_name=primary_region)
        secondary_rds = boto3.client('rds', region_name=secondary_region)
        
        logger.info(f"✅ Primary RDS client initialized for {primary_region}")
        logger.info(f"✅ Secondary RDS client initialized for {secondary_region}")
        
        # ====================================================================
        # STEP 3: RDS INSTANCE DISCOVERY & VALIDATION
        # ====================================================================
        logger.info("🔍 Discovering RDS instance details and validating existence...")
        
        # Query the RDS instance to get its configuration details
        # This ensures the instance exists and gets engine-specific information
        instance_response = primary_rds.describe_db_instances(
            DBInstanceIdentifier=db_instance_identifier
        )
        
        # Validate that the RDS instance exists
        if not instance_response['DBInstances']:
            raise ValueError(f"❌ RDS instance {db_instance_identifier} not found in {primary_region}")
        
        # Extract important instance details for backup operations
        db_instance = instance_response['DBInstances'][0]
        engine = db_instance.get('Engine')                    # e.g., 'oracle-se2', 'mysql', 'postgres'
        engine_version = db_instance.get('EngineVersion')     # e.g., '19.0.0.0.ru-2023-01.rur-2023-01.r1'
        instance_class = db_instance.get('DBInstanceClass')   # e.g., 'db.t3.micro'
        allocated_storage = db_instance.get('AllocatedStorage') # Storage size in GB
        
        logger.info(f"📋 RDS Instance Details:")
        logger.info(f"   🔧 Engine: {engine}")
        logger.info(f"   📦 Version: {engine_version}")
        logger.info(f"   💾 Instance Class: {instance_class}")
        logger.info(f"   💿 Storage: {allocated_storage} GB")
        logger.info("-" * 60)
        
        # ====================================================================
        # STEP 4: SNAPSHOT CREATION IN PRIMARY REGION
        # ====================================================================
        logger.info("📸 Creating manual snapshot in primary region...")
        
        # Generate unique snapshot identifier with timestamp
        # Format: instance-name-auto-backup-YYYY-MM-DD-HHMMSS
        timestamp = datetime.now().strftime('%Y-%m-%d-%H%M%S')
        snapshot_id = f"{db_instance_identifier}-auto-backup-{timestamp}"
        
        logger.info(f"🏷️  Snapshot ID: {snapshot_id}")
        logger.info(f"📅 Timestamp: {timestamp}")
        
        # Create the manual snapshot with comprehensive tagging
        # Tags help with identification, billing, and automation
        primary_rds.create_db_snapshot(
            DBInstanceIdentifier=db_instance_identifier,
            DBSnapshotIdentifier=snapshot_id,
            Tags=[
                {'Key': 'CreatedBy', 'Value': 'lambda-automation'},
                {'Key': 'BackupType', 'Value': 'automated-cross-region'},
                {'Key': 'SourceRegion', 'Value': primary_region},
                {'Key': 'CreatedAt', 'Value': timestamp},
                {'Key': 'Engine', 'Value': engine},
                {'Key': 'Purpose', 'Value': 'disaster-recovery'}
            ]
        )
        
        logger.info("✅ Snapshot creation initiated successfully")
        
        # ====================================================================
        # STEP 5: WAIT FOR SNAPSHOT COMPLETION
        # ====================================================================
        logger.info("⏳ Waiting for snapshot to complete (this may take several minutes)...")
        
        # Use AWS waiter to monitor snapshot progress
        # Waiter automatically polls the snapshot status until completion
        waiter = primary_rds.get_waiter('db_snapshot_completed')
        waiter.wait(
            DBSnapshotIdentifier=snapshot_id,
            WaiterConfig={
                'Delay': 30,        # Check every 30 seconds
                'MaxAttempts': 60   # Maximum 60 attempts = 30 minutes timeout
            }
        )
        
        logger.info("✅ Snapshot creation completed successfully!")
        
        # Retrieve the snapshot ARN needed for cross-region copying
        # ARN (Amazon Resource Name) uniquely identifies the snapshot across regions
        snapshot_response = primary_rds.describe_db_snapshots(
            DBSnapshotIdentifier=snapshot_id
        )
        snapshot_arn = snapshot_response['DBSnapshots'][0]['DBSnapshotArn']
        snapshot_size = snapshot_response['DBSnapshots'][0].get('AllocatedStorage', 'Unknown')
        
        logger.info(f"📋 Snapshot Details:")
        logger.info(f"   🔗 ARN: {snapshot_arn}")
        logger.info(f"   💿 Size: {snapshot_size} GB")
        logger.info("-" * 60)
        
        # ====================================================================
        # STEP 6: CROSS-REGION SNAPSHOT COPY
        # ====================================================================
        logger.info("🔄 Initiating cross-region snapshot copy...")
        
        # Generate target snapshot ID for secondary region
        # Format: original-snapshot-id-target-region
        target_snapshot_id = f"{snapshot_id}-{secondary_region}"
        
        logger.info(f"🎯 Target Region: {secondary_region}")
        logger.info(f"🏷️  Target Snapshot: {target_snapshot_id}")
        
        # Prepare copy parameters with encryption and tagging
        copy_params = {
            'SourceDBSnapshotIdentifier': snapshot_arn,          # Source snapshot ARN
            'TargetDBSnapshotIdentifier': target_snapshot_id,    # New snapshot name in target region
            'KmsKeyId': secondary_kms_key,                       # Encrypt with target region KMS key
            'CopyTags': True,                                    # Copy original tags
            'Tags': [                                            # Additional tags for tracking
                {'Key': 'BackupRegion', 'Value': secondary_region},
                {'Key': 'SourceSnapshot', 'Value': snapshot_id},
                {'Key': 'SourceRegion', 'Value': primary_region},
                {'Key': 'Method', 'Value': 'lambda-automation'},
                {'Key': 'Purpose', 'Value': 'cross-region-backup'},
                {'Key': 'CopiedAt', 'Value': datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
            ]
        }
        
        # Special handling for Oracle databases
        # Oracle may require specific option groups in the target region
        if engine.startswith('oracle') and secondary_option_group:
            copy_params['OptionGroupName'] = secondary_option_group
            logger.info(f"🔧 Oracle detected - Using option group: {secondary_option_group}")
        else:
            logger.info(f"🔧 Engine: {engine} - No special option group needed")
        
        # Execute the cross-region copy operation
        secondary_rds.copy_db_snapshot(**copy_params)
        logger.info("✅ Cross-region copy initiated successfully!")
        logger.info("-" * 60)
        
        # ====================================================================
        # STEP 7: CLEANUP OLD SNAPSHOTS (RETENTION POLICY)
        # ====================================================================
        logger.info("🧹 Starting cleanup of old snapshots based on retention policy...")
        
        # Call cleanup function to remove snapshots older than retention period
        # This prevents unlimited snapshot accumulation and controls storage costs
        cleanup_old_snapshots(primary_rds, secondary_rds, db_instance_identifier, retention_days)
        
        # ====================================================================
        # STEP 8: SUCCESS RESPONSE
        # ====================================================================
        logger.info("=" * 60)
        logger.info("🎉 BACKUP PROCESS COMPLETED SUCCESSFULLY!")
        logger.info("=" * 60)
        logger.info(f"✅ Primary Snapshot: {snapshot_id}")
        logger.info(f"✅ Secondary Snapshot: {target_snapshot_id}")
        logger.info(f"✅ Backup Time: {timestamp}")
        logger.info(f"✅ Retention: {retention_days} days")
        logger.info("=" * 60)
        
        # Return success response with operation details
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RDS cross-region backup completed successfully',
                'details': {
                    'primary_snapshot': snapshot_id,
                    'secondary_snapshot': target_snapshot_id,
                    'primary_region': primary_region,
                    'secondary_region': secondary_region,
                    'db_instance': db_instance_identifier,
                    'engine': engine,
                    'engine_version': engine_version,
                    'timestamp': timestamp,
                    'retention_days': retention_days
                }
            })
        }
        
    except Exception as e:
        # ====================================================================
        # ERROR HANDLING
        # ====================================================================
        logger.error("=" * 60)
        logger.error("❌ BACKUP PROCESS FAILED!")
        logger.error("=" * 60)
        logger.error(f"💥 Error Details: {str(e)}")
        logger.error(f"🎯 RDS Instance: {db_instance_identifier if 'db_instance_identifier' in locals() else 'Unknown'}")
        logger.error("=" * 60)
        
        # Re-raise the exception for Lambda error handling
        # This will trigger dead letter queue if configured
        raise


# ============================================================================
# CLEANUP FUNCTION - SNAPSHOT RETENTION MANAGEMENT
# ============================================================================
def cleanup_old_snapshots(primary_rds, secondary_rds, db_instance_identifier, retention_days):
    """
    🧹 Clean up old automated snapshots based on retention policy
    
    This function removes snapshots older than the specified retention period
    from both primary and secondary regions to control storage costs.
    
    Parameters:
        primary_rds: RDS client for primary region
        secondary_rds: RDS client for secondary region  
        db_instance_identifier: RDS instance identifier
        retention_days: Number of days to retain snapshots
    
    Process:
        1. Calculate cutoff date based on retention policy
        2. Query existing snapshots in both regions
        3. Identify snapshots older than cutoff date
        4. Delete old snapshots (with error handling)
    """
    try:
        # ====================================================================
        # CALCULATE RETENTION CUTOFF DATE
        # ====================================================================
        cutoff_date = datetime.now() - timedelta(days=retention_days)
        logger.info(f"🗓️  Retention cutoff date: {cutoff_date.strftime('%Y-%m-%d %H:%M:%S')}")
        logger.info(f"🧹 Cleaning snapshots older than {retention_days} days...")
        
        # ====================================================================
        # CLEANUP PRIMARY REGION SNAPSHOTS
        # ====================================================================
        logger.info(f"🔍 Scanning primary region ({primary_rds._client_config.region_name}) for old snapshots...")
        
        # Get all manual snapshots for this RDS instance
        primary_snapshots = primary_rds.describe_db_snapshots(
            DBInstanceIdentifier=db_instance_identifier,
            SnapshotType='manual'  # Only manual snapshots (not automated daily ones)
        )
        
        primary_deleted_count = 0
        for snapshot in primary_snapshots['DBSnapshots']:
            # Check if this is an automated backup snapshot that's too old
            if ('auto-backup' in snapshot['DBSnapshotIdentifier'] and 
                snapshot['SnapshotCreateTime'].replace(tzinfo=None) < cutoff_date):
                
                logger.info(f"🗑️  Deleting old primary snapshot: {snapshot['DBSnapshotIdentifier']}")
                primary_rds.delete_db_snapshot(
                    DBSnapshotIdentifier=snapshot['DBSnapshotIdentifier']
                )
                primary_deleted_count += 1
        
        logger.info(f"✅ Primary region cleanup: {primary_deleted_count} snapshots deleted")
        
        # ====================================================================
        # CLEANUP SECONDARY REGION SNAPSHOTS  
        # ====================================================================
        logger.info(f"🔍 Scanning secondary region ({secondary_rds._client_config.region_name}) for old snapshots...")
        
        # Get all manual snapshots in secondary region
        secondary_snapshots = secondary_rds.describe_db_snapshots(SnapshotType='manual')
        
        secondary_deleted_count = 0
        for snapshot in secondary_snapshots['DBSnapshots']:
            # Check if this snapshot belongs to our RDS instance and is too old
            if (snapshot['DBSnapshotIdentifier'].startswith(db_instance_identifier) and
                'auto-backup' in snapshot['DBSnapshotIdentifier'] and
                snapshot['SnapshotCreateTime'].replace(tzinfo=None) < cutoff_date):
                
                logger.info(f"🗑️  Deleting old secondary snapshot: {snapshot['DBSnapshotIdentifier']}")
                secondary_rds.delete_db_snapshot(
                    DBSnapshotIdentifier=snapshot['DBSnapshotIdentifier']
                )
                secondary_deleted_count += 1
        
        logger.info(f"✅ Secondary region cleanup: {secondary_deleted_count} snapshots deleted")
        logger.info(f"🧹 Total snapshots cleaned up: {primary_deleted_count + secondary_deleted_count}")
                
    except Exception as e:
        # Don't fail the main backup process due to cleanup issues
        # Log warning but continue with the backup operation
        logger.warning("⚠️  Cleanup process encountered errors (backup still successful):")
        logger.warning(f"   💥 Cleanup Error: {str(e)}")
        logger.warning("   🔄 Cleanup will be retried on next backup run")