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

from opentelemetry import trace
from opentelemetry.trace import SpanKind

FORMAT = '%(asctime)s - %(levelname)s - [trace_id=%(otelTraceID)s span_id=%(otelSpanID)s resource.service.name=%(otelServiceName)s] - %(message)s'
logger = logging.getLogger(__name__)
logger.setLevel("INFO")
h = logging.StreamHandler(sys.stdout)
h.setFormatter(logging.Formatter(FORMAT))
logger.addHandler(h)

logger.info("Starting Config query")

AGGREGATOR_NAME = os.getenv('AGGREGATOR_NAME')
REGION = os.getenv('REGION')
bucket_name = os.getenv('TAGGING_BUCKET')
bucket_prefix = os.getenv('BUCKET_PREFIX')
policy_table = os.getenv('POLICY_TABLE')
version_table = os.getenv('CLOUD_VERSION_TABLE')


def main(item, tries=1):
    try:
        client = boto3.client('config', region_name=REGION, config=Config(retries={'max_attempts': 10}))
        # SQL query to select all active EC2 instances
        query = "SELECT resourceType,resourceId,resourceName,configuration.targetResourceType,configuration.complianceType,configuration.configRuleList," \
                "configurationItemCaptureTime,configurationItemStatus,accountId,awsRegion " \
                "WHERE configuration.complianceType = 'NON_COMPLIANT' " \
                "AND resourceId LIKE '" + item + "%' " \
                "ORDER BY accountId DESC"

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
                    return main(tries+1)
                else:
                    logger.error("Attempted 3 Times But No Success.")
                    logger.error("Raising Exception.....")
                    raise
            else:
                logger.error(f"Error executing query : {str(e)}")
                raise

    except ClientError as e:
        if e.response['Error']['Code'] == 'ThrottlingException':
            if tries <= 3:
                logger.error("Throttling Exception Occured.")
                logger.error("Retrying.....")
                logger.error("Attempt No.: " + str(tries))
                time.sleep(3*tries)
                return main(tries+1)
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
