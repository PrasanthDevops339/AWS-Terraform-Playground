import boto3
import pandas as pd
import json
import logging
import os
import pysnow
import pymysql
from datetime import datetime
import io
from typing import Dict, List, Optional
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key
import sys
import opentelemetry.instrumentation.logging

opentelemetry.instrumentation.logging.LoggingInstrumentor().instrument(set_logging_format=True)
FORMAT = '%(asctime)s %(levelname)s [%(name)s] [%(filename)s:%(lineno)d] [trace_id=%(otelTraceID)s] [span_id=%(otelSpanID)s] resource.service.name=%(otelServiceName)s d_trace_sampled=%(otelTraceSampled)s - %(message)s'

logger = logging.getLogger(__name__)
logger.setLevel("INFO")
h = logging.StreamHandler(sys.stdout)
h.setFormatter(logging.Formatter(FORMAT))
logger.addHandler(h)

# ServiceNow instance parameters
SNOW_INSTANCE = os.environ.get('SNOW_INSTANCE', 'eriedev')
SECRET_NAME = os.environ.get('SNOW_SECRET_NAME', 'erieins-operations-dev-ServiceNowDevAPISecret')
DEFAULT_ASSIGNMENT_GROUP = os.environ.get('DEFAULT_ASSIGNMENT_GROUP', 'Cloud Enblmnt-cloud Operations')

# Use these for improved ticket categorization
TICKET_CATEGORY = os.environ.get('TICKET_CATEGORY', 'Application -> Other Issue')
TICKET_SUBCATEGORY = os.environ.get('TICKET_SUBCATEGORY', '')

# S3 bucket to read CSVs from
S3_BUCKET = os.environ.get('S3_BUCKET')
INGEST_PREFIX = os.environ.get('INGEST_PREFIX', 'ingest/aws-config/')

# Knowledge Base article URL
KB_ARTICLE_URL = os.environ.get(
    'KB_ARTICLE_URL',
    'https://service-now.com/kb_view.do?sys_kb_id=d409b489c3ea16d83354392f0501311f'
)

# get environment variables
db_host = os.environ["db_host"]
db_user = os.environ["db_user"]
db_port = os.environ["db_port"]
db_name = os.environ["db_name"]
region = os.environ["region"]
rules_table = os.environ["rules_table"]

# initialize boto3 clients
dynamodb = boto3.resource("dynamodb", region_name=region)
rds_client = boto3.client("rds")
s3_client = boto3.client("s3")


class SNOWRequests:
    def __init__(self, instance, username, password):
        self.instance = instance
        self.username = username
        self.password = password

    def makeConnection(self):
        try:
            client = pysnow.Client(instance=self.instance, user=self.username, password=self.password)
            return client
        except Exception as e:
            logger.error(f"Connection error: {e}")
            return f"Error: {e}"


class FollowOn(SNOWRequests):
    def __init__(self, instance, username, password, apiPath):
        super().__init__(instance, username, password)
        self.apiPath = apiPath
        self.client = self.makeConnection()
        self.followOnAPI = self.client.resource(api_path=self.apiPath)

    def openFollowOnTask(self, account_id, account_name, csv_path=None, csv_filename=None, support_group=None):
        """Create a follow-on task for tag compliance violations."""

        # Format description
        description = (
            f"Required backup, patching, and DR tag compliance violations have been detected "
            f"in the AWS account {account_name} (account number {account_id}).\n\n"
            f"For more information on how to correct these issues, please visit this knowledge base article:\n"
            f"KB Article: {KB_ARTICLE_URL}"
        )

        # Use provided support_group or fall back to default
        if support_group is None:
            support_group = DEFAULT_ASSIGNMENT_GROUP

        # Format account name for CI field
        formatted_account_name = account_name.lower()
        if not formatted_account_name.startswith('erieins-'):
            formatted_account_name = 'erieins-' + formatted_account_name
        parts = formatted_account_name.split('-')
        if len(parts) >= 3 and parts[-1].lower() in ['dev', 'tst', 'prd'] and parts[-2].lower() == parts[-1].lower():
            formatted_account_name = '-'.join(parts[:-1])

        # Create payload
        payload = {
            'assignment_group': support_group,
            'short_description': f'Tag Compliance Violations for AWS Account {account_name} (account number {account_id})',
            'description': description,
            'audit': 'IT Application Owner Certification',
            'cmdb_ci': formatted_account_name,  # Added CI field with formatted account name
        }

        # Create the follow-on task
        followOnTask = self.followOnAPI.create(payload=payload)
        followOnTaskID = followOnTask.one()['number']

        # If we have a CSV file, attach it
        if csv_path and csv_filename:
            try:
                attachment = self.followOnAPI.get(query={'number': followOnTaskID}).upload(file_path=csv_path)
                logger.info(f"Attached violations CSV to follow-on task {followOnTaskID}")
            except Exception as e:
                logger.error(f"Failed to attach CSV to follow-on task {followOnTaskID}: {e}")

        return followOnTask, followOnTaskID


def get_secret() -> Dict:
    """Retrieve ServiceNow credentials from AWS Secrets Manager."""
    secret_name = SECRET_NAME
    region_name = os.environ.get('AWS_REGION', 'us-east-2')

    try:
        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=region_name
        )
        response = client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except ClientError as e:
        logger.error(f"Failed to retrieve secret: {e}")
        raise


def load_support_groups_from_csv() -> Dict[str, str]:
    """Load account support groups from CMDB CI Accounts.csv file in S3."""
    account_support_groups = {}
    try:
        # Try to download the CSV from S3
        try:
            logger.info("Attempting to download CMDB CI Accounts CSV from S3...")
            s3_key = 'reference/CMDB_CI_Accounts.csv'  # Path in S3 bucket
            local_path = '/tmp/CMDB_CI_Accounts.csv'

            # Download the file
            s3_client.download_file(
                Bucket=S3_BUCKET,
                Key=s3_key,
                Filename=local_path
            )
            logger.info("Successfully downloaded CMDB CI Accounts CSV from S3")

            # Read the CSV file
            try:
                # Try UTF-8 first
                df = pd.read_csv(local_path)
            except UnicodeDecodeError:
                # If that fails, try with cp1252 encoding
                df = pd.read_csv(local_path, encoding='cp1252')

            # Log columns for debugging
            logger.info(f"CMDB CI Accounts CSV columns: {df.columns.tolist()}")

            # Map account IDs to support groups
            if 'Support Group' in df.columns and 'Account ID' in df.columns:
                for _, row in df.iterrows():
                    account_id = str(row['Account ID']).strip()
                    support_group = str(row['Support Group']).strip() if pd.notna(row['Support Group']) else ''
                    # Only add valid data
                    if account_id and support_group and account_id != 'nan' and support_group != 'nan':
                        account_support_groups[account_id] = support_group
                logger.info(f"Loaded support groups for {len(account_support_groups)} accounts")
            else:
                logger.warning("CMDB CI Accounts CSV doesn't contain expected columns. Could not load support groups.")
                logger.warning(f"Available columns: {df.columns.tolist()}")

        except Exception as e:
            logger.warning(f"Could not download or process CMDB CI Accounts CSV from S3: {e}")
            logger.warning("Will rely on default assignment group")

    except Exception as e:
        logger.error(f"Error loading support groups from CSV: {e}")

    return account_support_groups


def get_support_group(account_id: str) -> str:
    """Get the support group for an account using a multi-tier approach:
    1. Try CMDB CSV file from S3
    2. Fall back to default assignment group
    """

    # 1. First try loading from CMDB CSV
    support_groups = load_support_groups_from_csv()
    if account_id in support_groups:
        support_group = support_groups[account_id]
        logger.info(f"Found support group '{support_group}' for account {account_id} in CMDB CSV")
        return support_group

    # 2. Fall back to default assignment group
    logger.warning(f"No support group mapping found for account {account_id}, using default: {DEFAULT_ASSIGNMENT_GROUP}")
    return DEFAULT_ASSIGNMENT_GROUP


def read_csv_from_s3(s3_key: str) -> pd.DataFrame:
    """Read a CSV file from S3 into a pandas DataFrame."""
    try:
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=s3_key)

        # Read CSV content
        csv_content = response['Body'].read().decode('utf-8')
        return pd.read_csv(io.StringIO(csv_content))

    except Exception as e:
        logger.error(f"Error reading CSV file {s3_key}: {e}")
        return pd.DataFrame()


def download_csv_to_tmp(s3_key: str, account_id: str) -> Optional[str]:
    """Download a CSV file from S3 to the Lambda /tmp directory."""
    try:
        local_path = f"/tmp/{account_id}_{os.path.basename(s3_key)}"
        s3_client.download_file(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Filename=local_path
        )

        logger.info(f"Downloaded {s3_key} to {local_path}")
        return local_path

    except Exception as e:
        logger.error(f"Error downloading CSV file {s3_key}: {e}")
        return None


def create_snow_ticket(account_id: str, account_name: str, csv_path: str, target_type: str, action_details: Dict) -> Optional[str]:
    """Create a ServiceNow ticket (incident or follow-on task) for the account's violations."""
    try:
        # Get ServiceNow credentials
        creds = get_secret()
        for key, value in creds.items():
            creds_usr, creds_pwd = key, value

        # Format replacements for template variables
        replacements = {
            "{$ACCOUNT_NAMES}": account_name,
            "{$ACCOUNT_NUMBERS}": account_id,
            "{$KB_ARTICLE_URLS}": KB_ARTICLE_URL
        }

        # Get support group for this account
        support_group = get_support_group(account_id)

        # Format account name for CMDB CI
        formatted_account_name = account_name.lower()
        if not formatted_account_name.startswith('erieins-'):
            formatted_account_name = 'erieins-' + formatted_account_name
        parts = formatted_account_name.split('-')
        if len(parts) >= 3 and parts[-1].lower() in ['dev', 'tst', 'prd'] and parts[-2].lower() == parts[-1].lower():
            formatted_account_name = '-'.join(parts[:-1])

        # For template variable substitution
        short_description = action_details.get('ShortDescription', f'Tag Compliance Violations for AWS Account {account_name}')
        description = action_details.get('Description', (
            f"Required backup, patching, and DR tag compliance violations have been detected "
            f"in the AWS account {account_name} (account number {account_id}).\n\n"
            f"For more information on how to correct these issues, please visit this knowledge base article:\n"
            f"KB Article: {KB_ARTICLE_URL}"
        ))

        # Replace template variables
        for old, new in replacements.items():
            short_description = short_description.replace(old, new)
            description = description.replace(old, new)

        # Based on target type, create appropriate ticket
        if target_type.lower() == "task":
            # Create a follow-on task
            followOn = FollowOn(SNOW_INSTANCE, creds_usr, creds_pwd, '/table/cert_follow_on_task')
            task, task_number = followOn.openFollowOnTask(
                account_id=account_id,
                account_name=formatted_account_name,
                csv_path=csv_path,
                csv_filename=os.path.basename(csv_path),
                support_group=support_group
            )

            logger.info(f"Created follow-on task {task_number} for account {account_name}")
            return task_number

        else:  # Default to incident
            # Initialize ServiceNow connection
            snow = pysnow.Client(
                instance=SNOW_INSTANCE,
                user=creds_usr,
                password=creds_pwd
            )

            # Create incident resource
            incident_api = snow.resource(api_path='/table/incident')

            # Create incident payload
            payload = {
                'caller_id': 'CCOP_User',
                'assignment_group': support_group,
                'cmdb_ci': formatted_account_name,
                'impact': action_details.get('Impact', '3'),
                'urgency': action_details.get('Urgency', '3'),
                'short_description': short_description,
                'description': description,
                'work_notes': action_details.get('WorkNotes',
                    'A CSV file with the tag violations file been attached to this incident. '
                    'Please review and fix the tag compliance issues.'
                ),
                'u_category_list': TICKET_CATEGORY
            }

            # Add subcategory if provided
            if TICKET_SUBCATEGORY:
                payload['u_subcategory_list'] = TICKET_SUBCATEGORY

            # Create the incident
            logger.info(f"Creating incident with payload: {json.dumps(payload)}")
            incident = incident_api.create(payload=payload)

            # Get the incident number
            incident_info = incident.one()
            incident_number = incident_info['number']

            # Attach CSV file to the incident
            try:
                attachment = incident_api.get(query={'number': incident_number}).upload(file_path=csv_path)
                logger.info(f"Attached violations CSV to incident {incident_number}")
            except Exception as e:
                logger.error(f"Failed to attach CSV to incident {incident_number}: {e}")

            logger.info(f"Created incident {incident_number} for account {account_name}")
            return incident_number

    except Exception as e:
        logger.error(f"Failed to create ticket for account {account_id}: {e}")
        logger.error(f"Detailed error: {str(e)}")
        return None


def update_snow_ticket(account_id: str, account_name: str, csv_path: str, target_type: str, action_details: Dict, snow_ticket: Dict) -> Optional[str]:
    """Update a ServiceNow ticket (incident or follow-on task) for the account's violations."""
    try:
        # Get ServiceNow credentials
        creds = get_secret()
        for key, value in creds.items():
            creds_usr, creds_pwd = key, value

        # Based on target type, create appropriate ticket
        if target_type.lower() == "task":
            # Create a follow-on task
            followOn = FollowOn(SNOW_INSTANCE, creds_usr, creds_pwd, '/table/cert_follow_on_task')
            task, task_number = followOn.openFollowOnTask(
                account_id=account_id,
                account_name=formatted_account_name,
                csv_path=csv_path,
                csv_filename=os.path.basename(csv_path),
                support_group=support_group
            )

            logger.info(f"Created follow-on task {task_number} for account {account_name}")
            return task_number

        else:  # Default to incident
            # Initialize ServiceNow connection
            snow = pysnow.Client(
                instance=SNOW_INSTANCE,
                user=creds_usr,
                password=creds_pwd
            )

            # Create incident resource
            incident_api = snow.resource(api_path='/table/incident')
            snow_ticket = json.loads(snow_ticket)
            incident_record = incident_api.get(query={'number': snow_ticket['ticket_number']}).one()
            print("Record", incident_record)

            # Get the sys_id of the incident
            incident_sys_id = incident_record['sys_id']
            print("SYS", incident_sys_id)

            # Example: Get attachments for a specific incident record
            # Get the attachment resource
            attachment_res = snow.resource(api_path='/table/attachment')
            query = {
                'table_sys_id': incident_sys_id,
                'table_name': 'incident'
            }

            # Execute the query
            attachments = attachment_res.get(query=query).all()

            # Iterate through the results to get the sys_id of each attachment
            for attachment in attachments:
                old_sys_id = attachment['sys_id']

            print(f"Old sys_id:{old_sys_id}")

            # Delete the old attachment
            attachment_res.delete(query={'sys_id': old_sys_id})
            print(f"Attachment with sys_id {old_sys_id} deleted.")

            # Upload the file to the incident
            incident_api.attachments.upload(sys_id=incident_sys_id, file_path=csv_path)

            incident_number = incident_record['number']

            logger.info(f"Updated incident {incident_number} for account {account_name}")
            return incident_number

    except Exception as e:
        logger.error(f"Failed to update ticket for account {account_id}: {e}")
        logger.error(f"Detailed error: {str(e)}")
        raise
        return None


def lambda_handler(event, context):
    """Main Lambda handler."""
    # Retrieve the current count from the event

    try:
        logger.info("Starting CCOP ServiceNow ticket generation")
        logger.info(f"Event: {json.dumps(event)}")

        # Check if S3 bucket is configured
        if not S3_BUCKET:
            raise ValueError("S3_BUCKET environment variable is not set")

        # Get account info from the event
        source = event['source']
        account_id = event['accountId']
        account_name = event['accountName']
        rule_id = event['rule_id']
        snow_action_type = event['snow_action_type']

        #temporary
        if account_name:
            print(f"account_name : {account_name}")
            # Get IAM RDS auth token
            token = rds_client.generate_db_auth_token(DBHostname=db_host, Port=db_port, DBUsername=db_user, Region=region)

            # Connect to MySQL
            conn = pymysql.connect(
                auth_plugin_map={'mysql_clear_password': None},
                ssl_verify_identity=True,
                ssl_verify_cert=True,
                port=int(db_port),
                host=db_host,
                user=db_user,
                password=token,
                database=db_name
            )

        # Retrieve the latest pending action for this account and specific rule
        query = "SELECT * FROM actions WHERE source=%s AND accountId=%s AND ruleId=%s AND executed=0 ORDER BY timestamp DESC LIMIT 1"
        params = (source, account_id, rule_id)
        cursor = conn.cursor()
        with cursor as cursor:
            cursor.execute(query, params)
            rows = cursor.fetchall()
            print(f"rows : {rows}")

        # Format actions data
        account_files = []
        for row in rows:
            account_files.append({
                'account_id': account_id,
                'account_name': account_name,
                's3_key': row[5],
                'last_modified': datetime.now(),
                'snow_ticket': row[7]
            })

        print(account_files)

        # Process each account file and create tickets
        results = []
        for file_info in account_files:
            account_id = file_info['account_id']
            account_name = file_info['account_name']
            s3_key = file_info['s3_key']
            snow_ticket = file_info['snow_ticket']

            # Read CSV to get violation count
            df = read_csv_from_s3(s3_key)
            if df.empty:
                logger.warning(f"Empty or invalid CSV for account {account_name}, skipping")
                continue

            # Download CSV for attachment
            local_path = download_csv_to_tmp(s3_key, account_name)
            if not local_path:
                logger.error(f"Failed to download CSV for account {account_name}, skipping")
                continue

            # Get ticket configuration from DynamoDB
            table = dynamodb.Table(rules_table)
            response = table.query(KeyConditionExpression=Key('id').eq(int(rule_id)) & Key('source').eq('aws_config'))

            target_type = "incident"  # Default
            action_details = {}

            if 'Items' in response and response['Items']:
                actions_policy = response['Items'][0].get('actions_policy', '{}')
                action = json.loads(actions_policy)
                target_type = action.get('Action', {}).get('Type', 'incident')
                action_details = action.get('Action', {})

            if snow_action_type == "Create":
                # Create ServiceNow ticket (incident or follow-on task)
                print("In ticket Creation")
                ticket_number = create_snow_ticket(
                    account_id,
                    account_name,
                    local_path,
                    target_type,
                    action_details
                )
            elif snow_action_type == "Update":
                # Update ServiceNow ticket (incident or follow-on task)
                print("In ticket update")
                ticket_number = update_snow_ticket(
                    account_id,
                    account_name,
                    local_path,
                    target_type,
                    action_details,
                    snow_ticket
                )
            else:
                print("No ticket creation")

            if ticket_number:
                results.append({
                    'account_id': account_id,
                    'account_name': account_name,
                    'ticket_number': ticket_number,
                    'ticket_type': target_type
                })

                # Update the Actions table with results
                try:
                    sql = """
                    UPDATE actions SET executed=%s, state=%s WHERE source=%s AND accountId=%s AND ruleId=%s
                    """

                    state_data = {'ticket_number': ticket_number, 'ticket_type': target_type}
                    val = (1, json.dumps(state_data), source, account_id, rule_id)

                    cursor = conn.cursor()
                    cursor.execute(sql, val)
                    conn.commit()
                    print(f"cursor : {cursor.rowcount}")
                    print("Updated Actions table")
                except Exception as e:
                    logger.error(f"Error updating actions table: {e}")
                    raise
            else:
                logger.error(f"No ticket number")

            # Clean up local file
            try:
                os.remove(local_path)
            except:
                pass

        # Return results with state machine information
        logger.info(f"Created or Updated {len(results)} ServiceNow tickets")
        return {
            'statusCode': 200,
            'status': 'done',
            'body': {
                'message': f'Created or Updated {len(results)} ServiceNow tickets',
                'tickets': results
            }
        }

    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'message': 'Error creating ServiceNow tickets',
                'error': str(e)
            }
        }
