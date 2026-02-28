import pymysql
import sys
import boto3
import os
import json

#variables needed to connect to database
REGION = "us-east-2"
PORT = 3306
os.environ['LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN'] = '1'
DBNAME = os.environ['database_name']
ENDPOINT = os.environ['proxy_host_name']
secret_name = os.environ['database_secret_arn']

#create secret manager boto3 session
secretsManager = boto3.client('secretsmanager')

#extract secret data
response = secretsManager.get_secret_value(SecretId=secret_name)

#load secret into a dictionary
secret_dict = json.loads(response['SecretString'])

#pull username and password from dictionary
username = secret_dict['username']
password = secret_dict['password']

#make database connection
try:
    conn = pymysql.connect(host=ENDPOINT, user=username, passwd=password, db=DBNAME, connect_timeout=5)
except pymysql.MySQLError as e:
    logger.error("ERROR: Unexpected error: Could not connect to MySQL instance.")
    logger.error(e)
    sys.exit(1)


def lambda_handler(event, context):

    #Perform database tasks.

    #Create Cursor
    cur = conn.cursor()

    #Load mysql_config.txt and process each line of the file as a database command.
    with open("mysql_config.txt", 'r') as file:
        #Loop through each line of the file and store it in the 'line' variable.
        for line in file:
            # Process each line of the file as its own command.
            print(f"Issuing Next command: {line}")
            try:
                #execute database command in 'line'
                cur.execute(line)
                #get command result and store in 'query_results'
                query_results = cur.fetchall()
                #Print command to terminal/cloudwatch logs
                print(f"Command Result: {query_results}")
            except Exception as e:
                #Print error message to terminal/cloudwatch logs
                print("Database connection failed due to {}".format())
                #Continue processing if single command fails.
                continue