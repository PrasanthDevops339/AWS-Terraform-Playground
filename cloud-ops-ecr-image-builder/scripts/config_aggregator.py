"""
AWS Config Aggregator Query Script

Purpose:
    Queries AWS Config aggregator for non-compliant resources across multiple accounts.
    Retrieves resource compliance data and stores results for reporting/remediation.

Features:
    - Cross-account Config data aggregation
    - SQL-based querying of resource configurations
    - OpenTelemetry tracing for observability
    - Pagination handling for large result sets
    - Integration with DynamoDB for data persistence

Environment Variables Required:
    - AGGREGATOR_NAME: Name of the AWS Config aggregator
    - REGION: AWS region for Config queries
    - TAGGING_BUCKET: S3 bucket for storing results
    - BUCKET_PREFIX: S3 key prefix for organizing data
    - POLICY_TABLE: DynamoDB table for policy tracking
    - CLOUD_VERSION_TABLE: DynamoDB table for version tracking

Usage:
    Called by orchestration script with resource type filter
    Example: main('vol-')  # Query EBS volumes

Output:
    Returns non-compliant resources with:
    - Resource type and ID
    - Compliance status and rule violations
    - Account and region information
    - Configuration capture timestamp
"""

# scripts/config_aggregator.py

import json
import boto3
import io
import csv
import os
import time
import pandas as pd
from datetime import datetime
from botocore.config import Config
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key, Attr
import sys
import logging

# OpenTelemetry for distributed tracing
from opentelemetry import trace
from opentelemetry.trace import SpanKind

# Configure logging with OpenTelemetry trace context
FORMAT = '%(asctime)s - %(levelname)s - [trace_id=%(otelTraceID)s span_id=%(otelSpanID)s resource.service.name=%(otelServiceName)s] - %(message)s'
logger = logging.getLogger(__name__)
logger.setLevel("INFO")
h = logging.StreamHandler(sys.stdout)
h.setFormatter(logging.Formatter(FORMAT))
logger.addHandler(h)

logger.info("Starting Config query")

# Load configuration from environment variables
AGGREGATOR_NAME = os.getenv('AGGREGATOR_NAME')  # Config aggregator name
REGION = os.getenv('REGION')                    # AWS region
bucket_name = os.getenv('TAGGING_BUCKET')       # S3 bucket for results
bucket_prefix = os.getenv('BUCKET_PREFIX')      # S3 object key prefix
policy_table = os.getenv('POLICY_TABLE')        # DynamoDB policy table
version_table = os.getenv('CLOUD_VERSION_TABLE') # DynamoDB version table

# ============================================================================
# SUSPENDED OU CONFIGURATION
# ============================================================================
# Hardcoded OU ID for the Suspended OU. All accounts under this OU will be
# excluded from compliance reporting. Update this if your Suspended OU changes.
# ============================================================================
SUSPENDED_OU_ID = 'ou-susp345jkl'  # Update this with your actual Suspended OU ID
# ============================================================================


def main(item, tries=1):
    """
    Main query function for AWS Config aggregator.
    
    Args:
        item (str): Resource ID prefix to filter query (e.g., 'vol-' for EBS volumes)
        tries (int): Retry attempt number (for error handling)
        
    Returns:
        list: Non-compliant resources matching the filter
        
    Process:
        1. Construct SQL query for Config aggregator
        2. Execute query with pagination
        3. Process and format results
        4. Handle retries on failures
        
    Query Logic:
        - Selects resources with NON_COMPLIANT status
        - Filters by resource ID prefix
        - Orders by account ID
        - Returns resource configuration and compliance details
    """
    # Initialize AWS Config client with retry configuration
    client = boto3.client('config', region_name=REGION, config=Config(retries={'max_attempts': 10}))
    
    # SQL query to select all non-compliant resources matching the filter
    # Query structure:
    #   - resourceType: Type of AWS resource (e.g., AWS::EC2::Volume)
    #   - resourceId: Unique resource identifier
    #   - configuration.complianceType: Compliance status
    #   - configuration.configRuleList: Rules that evaluated the resource
    query = "SELECT resourceType,resourceId,resourceName,configuration.targetResourceType,configuration.complianceType,configuration.configRuleList," \
            "configurationItemCaptureTime,configurationItemStatus,accountId,awsRegion " \
            "WHERE configuration.complianceType = 'NON_COMPLIANT' " \
            "AND resourceId LIKE '" + item + "%' " \
            "ORDER BY accountId DESC"

    # Optional: Add time filter for recent violations only
    # "AND configurationItemCaptureTime >= '2025-09-15T00:00:00Z'" \
    #logger.info(query)

    results = []

    try:
        # Initialize the nextToken as None to start the loop
        next_token = None
        # Loop to handle pagination with nextToken
        while True:
            # Execute the query with the current nextToken
            if next_token:
                response = client.select_aggregate_resource_config(
                    Expression=query,
                    ConfigurationAggregatorName=AGGREGATOR_NAME,
                    NextToken=next_token
                )
            else:
                response = client.select_aggregate_resource_config(
                    Expression=query,
                    ConfigurationAggregatorName=AGGREGATOR_NAME
                )

            #logger.info("Response", response)

            # Process the results (for example, logger.info them)
            results.extend(response['Results'])

            # Check if there is a nextToken to continue fetching more results
            next_token = response.get('NextToken')

            # If no nextToken, break out of the loop
            if not next_token:
                break

        return results

    except ClientError as e:
        if e.response['Error']['Code'] == 'ThrottlingException':
            if tries <= 3:
                logger.error("Throttling Exception Occured.")
                logger.error("Retrying.....")
                logger.error("Attempt No.: " + str(tries))
                time.sleep(3*tries)
                return main(item, tries+1)
            else:
                logger.error("Attempted 3 Times But No Success.")
                logger.error("Raising Exception.....")
                raise
        else:
            logger.error(f"Error executing query : {str(e)}")
            raise


# A cache to store annotations once they've been fetched
annotation_cache = {}


def get_rule_description(rule_name, account_id, region, rule_ann):
    client = boto3.client('config', region_name=REGION, config=Config(retries={'max_attempts': 10}))

    cache_key = (rule_name, account_id, region)

    if cache_key in annotation_cache:
        return annotation_cache[cache_key]

    detail_paginator = client.get_paginator('get_aggregate_compliance_details_by_config_rule')
    detail_iterator = detail_paginator.paginate(
        ConfigurationAggregatorName=AGGREGATOR_NAME,
        ConfigRuleName=rule_name,
        AccountId=account_id,
        AwsRegion=region,
        ComplianceType='NON_COMPLIANT'
    )
    for details_page in detail_iterator:
        for result in details_page['AggregateEvaluationResults']:
            if 'Annotation' in result:
                if "*" in rule_ann:
                    ruleann_check = True
                else:
                    ruleann_check = any(item in result['Annotation'] for item in rule_ann)
                if ruleann_check:
                    description = result['Annotation']
                    logger.info(f"In subset desc {result['Annotation']}")
                else:
                    logger.info("No subset: continuing")
                    continue
            else:
                description = ''
            annotation_cache[cache_key] = description
            return description


def get_account_name(account_id):
    try:
        org_client = boto3.client('organizations')
        response = org_client.describe_account(AccountId=account_id)
        account_name = response.get('Account', {}).get('Name')
        return account_name
    except Exception as e:
        logger.error(f"Error getting account name: {e}")
        return None


# A cache to store account names once they've been fetched
account_cache = {}


def get_account_name_cached(account_id):
    # Check if the account name is already cached
    if account_id not in account_cache:
        # If not cached, fetch and store it
        account_cache[account_id] = get_account_name(account_id)
    return account_cache[account_id]


def check_account(account_name):
    # Check if the account is in dynamo to determine 1.0 or 2.0
    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table(version_table)

    try:
        response = table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('account_name').eq(account_name)
        )

        # Check if the 'Items' list in the response is not empty
        if bool(response.get('Items')):
            return True
        else:
            return False

    except ClientError as e:
        logger.error(f"Error in Dynamo query: {e}")
        return False


# ============================================================================
# SUSPENDED OU EXCLUSION - START
# ============================================================================
# This function checks if an account is in the 'Suspended' OU and excludes it
# from compliance reporting. Accounts in suspended OUs are skipped entirely.
# Uses hardcoded OU ID (SUSPENDED_OU_ID) for fast, reliable checking.
# ============================================================================
def is_account_in_suspended_ou(account_id):
    """
    Check if an account belongs to the Suspended OU (or any of its children).
    
    Returns True if the account is under the SUSPENDED_OU_ID, False otherwise.
    
    This is more efficient than name-based checking:
    - OU IDs don't change (names can be renamed)
    - Direct ID comparison is faster
    - No case-sensitivity issues
    
    Example org structure:
        Root
        ├── infrastructure (ou-test123abc)
        ├── Suspended (ou-susp345jkl)  <- SUSPENDED_OU_ID - Accounts here excluded
        └── workloads (ou-prod678uvw)
    """
    try:
        org_client = boto3.client('organizations')
        
        # Walk up the OU hierarchy from the account to root
        current_id = account_id
        ou_path = []
        
        while True:
            # Get parent of current entity
            response = org_client.list_parents(ChildId=current_id)
            
            if not response.get('Parents'):
                break
                
            parent = response['Parents'][0]  # An account/OU has only one parent
            
            # If we've reached the root, stop
            if parent['Type'] == 'ROOT':
                ou_path.append(('Root', parent['Id']))
                break
            
            # If it's an OU, check if it matches the suspended OU ID
            if parent['Type'] == 'ORGANIZATIONAL_UNIT':
                ou_id = parent['Id']
                
                # DIRECT OU ID CHECK - Fast and reliable
                if ou_id == SUSPENDED_OU_ID:
                    ou_response = org_client.describe_organizational_unit(OrganizationalUnitId=ou_id)
                    ou_name = ou_response.get('OrganizationalUnit', {}).get('Name', '')
                    logger.warning(f"[SUSPENDED OU DETECTED] Account {account_id} is under Suspended OU")
                    logger.warning(f"   OU Name: '{ou_name}' | OU ID: {ou_id}")
                    return True
                
                # Get OU name for logging path (optional)
                ou_response = org_client.describe_organizational_unit(OrganizationalUnitId=ou_id)
                ou_name = ou_response.get('OrganizationalUnit', {}).get('Name', '')
                ou_path.append((ou_name, ou_id))
                
                # Move up to the next level
                current_id = ou_id
            else:
                break
        
        # Log the full OU path for debugging
        ou_path.reverse()
        path_str = ' -> '.join([f"{name}" for name, _ in ou_path])
        logger.info(f"[DEBUG] Account {account_id} OU Path: {path_str}")
        logger.info(f"[OK] Account {account_id} is NOT in suspended OU")
        return False
        
    except Exception as e:
        logger.error(f"[ERROR] Error checking OU for account {account_id}: {e}")
        # In case of error, assume not suspended to avoid accidentally skipping valid accounts
        return False

# ============================================================================
# SUSPENDED OU EXCLUSION - END
# ============================================================================


if __name__ == '__main__':
    tracer = trace.get_tracer(__name__)
    with tracer.start_as_current_span("GetConfig", kind=SpanKind.SERVER):
        now = datetime.now()
        # Format the time
        current_time = now.strftime("%H:%M:%S")
        # logger.info the current time
        logger.info(f"Current Time: {current_time}")

        #get what to get from aws config using dynamo db table
        dynamodb = boto3.resource('dynamodb', region_name=REGION)
        table = dynamodb.Table(policy_table)

        try:
            # Perform the query with boolean filter
            response = table.query(
                KeyConditionExpression=Key('source').eq('aws_config'),
                FilterExpression=Attr('enabled').eq(True)
            )

            if 'Items' in response and response['Items']:
                ingest_policy = response['Items'][0].get('ingest_policy', '{}')
                rule_id = response['Items'][0].get('id', 1)
                ingest = json.loads(ingest_policy)
                res_types = ingest.get('ResourceTypes', {})
                rule_ann = ingest.get('Annotations', {})
                rule_type = ingest.get('Rules', {})
                comp_type = ingest.get('ComplianceType', 'NON_COMPLIANT')

                logger.info(f"res types: {res_types}")
                logger.info(f"rann {rule_ann}")
                logger.info(f"rtype {rule_type}")
                logger.info(f"comp {comp_type}")

                # Write to CSV in memory
                csv_buffer = io.StringIO()
                fieldnames = ['resourceId', 'resourceType', 'resourceName', 'targetResourceType', 'complianceType', 'configRuleName',
                              'configurationItemCaptureTime', 'configurationItemStatus', 'accountId', 'accountName', 'awsRegion', 'description']
                writer = csv.DictWriter(csv_buffer, fieldnames=fieldnames)
                writer.writeheader()

                for item in res_types:
                    logger.info(item)
                    results = main(item)

                    n1 = datetime.now()
                    t1 = n1.strftime("%H:%M:%S")
                    logger.info(f"After res {t1}")

                    for item in results:
                        parsed_results = json.loads(item)
                        resource_id = parsed_results.get('resourceId')
                        resource_name = parsed_results.get('resourceName')
                        resource_type = parsed_results.get('resourceType')
                        target_res_type = parsed_results.get('configuration', {}).get('targetResourceType')
                        compliance_type = parsed_results.get('configuration', {}).get('complianceType')
                        capture_time = parsed_results.get('configurationItemCaptureTime')
                        status = parsed_results.get('configurationItemStatus')
                        account_id = parsed_results.get('accountId')
                        account_name = get_account_name_cached(account_id)
                        
                        # ================================================================
                        # SUSPENDED OU CHECK: Exclude accounts from Suspended OU
                        # If account is in a Suspended OU, skip it entirely from reporting
                        # ================================================================
                        if is_account_in_suspended_ou(account_id):
                            logger.warning(f"[SUSPENDED OU] Skipping account: {account_id} ({account_name})")
                            continue
                        # ================================================================
                        
                        region = parsed_results.get('awsRegion')
                        config_rule_name = []
                        config_annotation = []

                        for rule in parsed_results.get('configuration', {}).get('configRuleList', []):
                            if "*" in rule_type:
                                rule_check = True
                            else:
                                rule_check = any(item in rule.get('configRuleName') for item in rule_type)
                            if rule.get('complianceType') == comp_type and rule_check:
                                annotation = get_rule_description(rule.get('configRuleName'), account_id, region, rule_ann)
                                config_rule_name.append(rule.get('configRuleName'))
                                config_annotation.append(annotation)
                            else:
                                continue

                        #check if its 2.0 and then insert into list
                        if not check_account(account_name) and config_annotation:
                            # not 1.0 account
                            writer.writerow({
                                'resourceId': resource_id, 'resourceType': resource_type, 'resourceName': resource_name,
                                'targetResourceType': target_res_type, 'complianceType': compliance_type, 'configRuleName': config_rule_name,
                                'configurationItemCaptureTime': capture_time, 'configurationItemStatus': status,
                                'accountId': account_id, 'accountName': account_name, 'awsRegion': region, 'description': config_annotation
                            })
                        else:
                            logger.info(f"Account {account_id} & {account_name} are 1.0")

                n = datetime.now()
                time = n.strftime("%H:%M:%S")
                logger.info(f"After csv: {time}")

                # Read the CSV buffer into a pandas DataFrame
                try:
                    logger.info("Reading csv to df")
                    csv_buffer.seek(0)
                    df = pd.read_csv(csv_buffer)
                except pd.errors.EmptyDataError:
                    logger.error("Input CSV buffer is empty.")
                except Exception as e:
                    logger.error(f"Error reading CSV buffer: {e}")

                # Group the DataFrame by the specified columns
                logger.info("Grouping data")
                logger.info(df)
                grouped_data = df.groupby(['accountId', 'accountName'])
                logger.info(f"Grouped data {grouped_data}")

                logger.info(f"Found {len(grouped_data)} unique account groups.")

                # Iterate over each group and upload to S3
                for group_keys, group_df in grouped_data:
                    # Create a safe file name from the grouping keys
                    # Convert tuple to string, e.g., (101, 'John Doe') -> '101_John Doe'
                    if isinstance(group_keys, tuple):
                        group_key_str = '-'.join(str(key) for key in group_keys)
                    else:
                        group_key_str = str(group_keys)

                    # Create an in-memory buffer for the group's CSV data
                    csv_out_buffer = io.StringIO()
                    group_df.to_csv(csv_out_buffer, index=False)
                    csv_out_buffer.seek(0)

                    # Upload to S3
                    try:
                        now = datetime.now()
                        timestamp = now.timestamp()
                        logger.info(timestamp)
                        object_key = f'{bucket_prefix}/{group_key_str}_{rule_id}.csv'

                        s3 = boto3.client('s3', region_name=REGION)
                        s3.put_object(
                            Bucket=bucket_name,
                            Key=object_key,
                            Body=csv_out_buffer.getvalue()
                        )

                        logger.info(f"CSV saved to s3://{bucket_name}/{object_key}")

                    except ClientError as e:
                        logger.error(f"Error uploading to s3 with key {key}: {e}")

            else:
                logger.info("No enabled rules")

        except ClientError as e:
            logger.error(f"Error in Dynamo query: {e}")
        trace.get_tracer_provider().shutdown()
