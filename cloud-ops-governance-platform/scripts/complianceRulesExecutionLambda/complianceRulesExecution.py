# complianceRulesExecution.py

# imports
import csv
import io
import os
import boto3
import json
import hashlib
import pymysql
from datetime import datetime
import traceback
import logging
import sys
import opentelemetry.instrumentation.logging

opentelemetry.instrumentation.logging.LoggingInstrumentor().instrument(set_logging_format=True)
FORMAT = '%(asctime)s %(levelname)s [%(name)s] [%(filename)s:%(lineno)d] [trace_id=%(otelTraceID)s] ' \
         ' span_id=%(otelSpanID)s resource.service.name=%(otelServiceName)s trace_sampled=%(otelTraceSampled)s] - %(message)s'

logger = logging.getLogger(__name__)
logger.setLevel("INFO")
h = logging.StreamHandler(sys.stdout)
h.setFormatter(logging.Formatter(FORMAT))
logger.addHandler(h)

# get environment variables
db_host = os.environ["db_host"]
db_user = os.environ["db_user"]
db_port = os.environ["db_port"]
db_name = os.environ["db_name"]
s3_bucket = os.environ["s3_bucket"]
rules_table = os.environ["dynamo_table"]
region = os.environ["region"]

# initialize boto3 clients
dynamo_client = boto3.client("dynamodb", region_name=region)
rds_client = boto3.client("rds")
s3_client = boto3.client("s3")


# lambda handler entry point
def lambda_handler(event, context):
    try:
        # get execution rules from ccops dynamo execution rules table
        items = []
        #response = dynamo_client.scan(TableName=rules_table)
        response = dynamo_client.scan(
            TableName=rules_table,
            FilterExpression="#en = :val",
            ExpressionAttributeNames={
                "#en": "enabled"  # Using an alias to avoid potential reserved word conflicts
            },
            ExpressionAttributeValues={
                ":val": {"BOOL": True}  # Explicitly define value as a Boolean
            }
        )

        rules = response["Items"]
        source = event["source"]
        account_id = event["accountId"]
        account_name = event["accountName"]
        print(f"Rules : {rules}")

        # get iam rds auth token
        token = rds_client.generate_db_auth_token(DBHostname=db_host, Port=db_port, DBUsername=db_user, Region=region)

        # Connect to MySQL
        conn = pymysql.connect(
            auth_plugin_map={"mysql_clear_password": None},
            ssl_verify_identity=True,
            ssl_verify_cert=True,
            port=int(db_port),
            host=db_host,
            user=db_user,
            password=token,
            database=db_name
        )

        query = "SELECT * FROM ingest WHERE source=%s AND accountId=%s"
        params = (source, account_id)
        cursor = conn.cursor()
        with cursor as cursor:
            cursor.execute(query, params)
            rows = cursor.fetchall()

        # get date
        now = datetime.now()
        date = now.strftime("%m%d%Y")
        print(f"rows : {rows}")

        if rows:
            print(f"In rows : {rows}")

            snow_action_type = ''
            matched_rule = None

            # match execution rules to ingest data — outer loop over rules, collect ALL matching rows
            for rule in rules:
                rule_id = list(rule['id'].values())[0]
                print(f"rule_id : {rule_id}")

                # collect ALL ingest rows that match this rule (not just the first)
                data = []
                for row in rows:
                    print(f"row[1] : {row[1]}")
                    if int(rule_id) == row[1]:
                        data.append(list(row))

                # test to see if there are any matching records in ingest
                if not data:
                    print(f"No match on {rule['id']} - {rule['description']}")
                    continue

                matched_rule = rule_id
                print(f"data = {data}")
                # sort data to generate consistent hash and hash ingest records to detect changes
                sorted_data = sorted(data, key=lambda x: (x[2], x[5], x[7], x[8], x[13]))
                print(f"sorted data = {sorted_data}")
                data_to_hash = json.dumps(sorted_data).encode('utf-8')
                hashed = hashlib.sha256(data_to_hash).hexdigest()
                print(f"ingest hash = {hashed}")

                # write sorted matching ingest records in memory csv buffer
                csv_buffer = io.StringIO()
                csv_writer = csv.writer(csv_buffer)
                csv_writer.writerow(['source','id','accountId','accountName','cloudVersion','region','resourceType','resourceId','resourceName',
                                     'targetresourceType','compliance','description','creationDate','details','status'])
                csv_writer.writerows(sorted_data)

                # write in memory csv to s3
                s3_key = f"processed/{source}/{account_id}/{matched_rule}_{date}.csv"
                csv_content = csv_buffer.getvalue()
                s3_client.put_object(
                    Bucket=s3_bucket,
                    Key=s3_key,
                    Body=csv_content
                )

                # output match results
                print(f"match on {rule['id']} - {rule['description']}")

                try:
                    current_datetime = datetime.now()
                    current_timestamp = current_datetime.strftime("%Y-%m-%d %H:%M:%S")
                    print("Timestamp:", current_timestamp)
                    print("artifact: ", s3_key)

                    sql = """
INSERT INTO actions(accountId, ruleId, hash, executed, timestamp, state, artifact, source)
VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE hash = VALUES(hash),
executed = VALUES(executed),
timestamp = VALUES(timestamp)
"""

                    val = (account_id, rule_id, hashed, 'FALSE', current_timestamp, '[]', s3_key, source)
                    cursor = conn.cursor()
                    # execute insert
                    cursor.execute(sql, val)
                    conn.commit()
                    print("Inserted or updated the Actions table")
                    if cursor.rowcount == 1:
                        print("Row inserted successfully.")
                        snow_action_type = 'Create'
                    elif cursor.rowcount == 2:
                        print("Row updated successfully.")
                        snow_action_type = 'Update'
                    elif cursor.rowcount == 0:
                        print("Row already existed and no hash changes")
                        snow_action_type = ''
                except Exception as e:
                    logger.error(f"Error inserting into actions table: {e}")
                    raise

            # after all rules are processed, delete ingest records once
            try:
                sql = """
DELETE FROM ingest WHERE accountId=%s AND source=%s
"""
                val = (account_id, source)
                cursor = conn.cursor()
                # execute delete
                cursor.execute(sql, val)
                conn.commit()
                print("Deleted from ingest")
            except Exception as e:
                logger.error(f"Error deleting from ingest table: {e}")
                raise

            return {
                "statusCode": 200,
                "body": f"rule execution for source {source} account {account_id} complete",
                "source": source,
                "accountId": account_id,
                "accountName": account_name,
                "rule_id": matched_rule if matched_rule else '',
                "snow_action_type": snow_action_type
            }

        else:
            return {
                "statusCode": 200,
                "body": f"No records found for source {source} account {account_id} complete",
                "source": source,
                "accountId": account_id,
                "accountName": account_name,
                "rule_id": '',
                "snow_action_type": ''
            }

    except Exception as e:
        print(f"Error Processing Rules Execution Lambda: {str(e)}")
        logging.error(traceback.format_exc())
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
