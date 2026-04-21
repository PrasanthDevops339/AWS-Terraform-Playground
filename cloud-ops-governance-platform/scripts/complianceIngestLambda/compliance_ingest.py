# compliance_ingest.py

import boto3
import pymysql
import csv
import io
import os
import botocore
import traceback
import logging
import sys
import opentelemetry.instrumentation.logging

opentelemetry.instrumentation.logging.LoggingInstrumentor().instrument(set_logging_format=True)
FORMAT = '%(asctime)s %(levelname)s [%(name)s] [%(filename)s:%(lineno)d] [trace_id=%(otelTraceID)s] span_id=%(otelSpanID)s resource.service.name=%(otelServiceName)s trace_sampled=%(otelTraceSampled)s] - %(message)s'"

logger = logging.getLogger(__name__)
logger.setLevel("INFO")
h = logging.StreamHandler(sys.stdout)
h.setFormatter(logging.Formatter(FORMAT))
logger.addHandler(h)

s3_client = boto3.client('s3', 'us-east-2', config=botocore.config.Config(s3={'addressing_style': 'path'}))
# initialize boto3 clients
#s3_client = boto3.client("s3")
rds_client = boto3.client("rds")
kms = boto3.client("kms")

# get lambda environment variables
db_host = os.environ["db_host"]
db_user = os.environ["db_user"]
db_port = os.environ["db_port"]
db_name = os.environ["db_name"]
region = os.environ["region"]
os.environ['LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN'] = '1'


def lambda_handler(event, context):
    try:
        # get S3 bucket and file key from event trigger
        bucket_name = event["detail"]["bucket"]["name"]
        file_key = event["detail"]["object"]["key"]

        print(f"processing ingest: s3://{bucket_name}/{file_key}")

        s3_path = "s3://" + bucket_name + "/" + file_key
        print(s3_path)

        source = s3_path.split("/")[4]
        acc_det = s3_path.split("/")[5]
        account_id = acc_det.split("_")[0]
        r_id = acc_det.split("_")[2].removesuffix(".csv")
        account_name = acc_det.split("_")[1].removesuffix(".csv")
        print("Account_id & account Name:", account_id, account_name)

        print("Source:", source)
        # r_id = 1 #temp value

        # read csv file from S3 into memory
        print(bucket_name, file_key)
        response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        decoded_file = response["Body"].read().decode("utf-8")
        print(decoded_file)

        # parse csv data
        data = []
        csv_reader = csv.reader(io.StringIO(decoded_file))
        next(csv_reader)  # skip header row
        for row in csv_reader:
            # convert each row into a tuple
            data.append((source, r_id, row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10], row[11], '2.0'))

        print(f"extracted {len(data)} records from ingest csv")

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

        cursor = conn.cursor()

        #(source, id, accountId, accountName,
        #cloudVersion, region, resourceType, resourceId, creationDate, details)

        # sql query to insert only new records (duplicates are ignored)
        sql = """
INSERT IGNORE INTO ingest(source,id,resourceId,resourceType,resourceName,targetResourceType,complianceType,configRuleName,itemCaptureTime,
itemStatus,accountId,accountName,awsRegion,description,cloudVersion)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
"""

        # execute batch insert
        cursor.executemany(sql, data)
        conn.commit()

        print(f"=ingest for {file_key} complete - {cursor.rowcount} records inserted (duplicates ignored)")

        # Close connection
        cursor.close()
        conn.close()

        return {
            "statusCode": 200,
            "body": f"Ingest for {file_key} complete - inserted {cursor.rowcount} records",
            "source": source,
            "accountId": account_id,
            "accountName": account_name
        }

    except Exception as e:
        print(f"Error Processing Ingest Lambda: {str(e)}")
        logging.error(traceback.format_exc())
        return {"statusCode": 500, "body": str(e)}
