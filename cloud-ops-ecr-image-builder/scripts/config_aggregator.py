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

FORMAT = '%(asctime)s - %(levelname)s - [trace_id=%(trace_id)s] - %(message)s'
logger = logging.getLogger(__name__)
logger.setLevel("INFO")
h = logging.StreamHandler(sys.stdout)
h.setFormatter(logging.Formatter(FORMAT))
logger.addHandler(h)

logger.info("Starting Config query", extra={"trace_id": "-"})

AGGREGATOR_NAME = os.getenv('AGGREGATOR_NAME')
REGION = os.getenv('REGION')
bucket_name = os.getenv('TAGGING_BUCKET')
bucket_prefix = os.getenv('BUCKET_PREFIX')
policy_table = os.getenv('POLICY_TABLE')
version_table = os.getenv('CLOUD_VERSION_TABLE')


def main(item, tries=1):
    """
    NOTE: The screenshot shows this function exists and begins by creating a boto3 config client
    and building a Config Aggregator SQL query string.

    The exact query text is NOT fully visible in the screenshot, so this implementation will NOT
    invent it. Provide the query via env var CONFIG_AGG_QUERY.
    """
    if not REGION:
        raise RuntimeError("Missing env var REGION")
    if not AGGREGATOR_NAME:
        raise RuntimeError("Missing env var AGGREGATOR_NAME")

    client = boto3.client('config', region_name=REGION, config=Config(retries={"max_attempts": 10, "mode": "standard"}))

    # SQL query to select all active EC2 instances...
    query = os.getenv("CONFIG_AGG_QUERY")
    if not query:
        raise RuntimeError("Missing env var CONFIG_AGG_QUERY (query not readable from screenshot)")

    try:
        resp = client.select_aggregate_resource_config(
            ConfigurationAggregatorName=AGGREGATOR_NAME,
            Expression=query
        )
        return resp
    except ClientError as e:
        logger.error("Config aggregator query failed", extra={"trace_id": "-"})
        raise


if __name__ == "__main__":
    # The screenshot shows the file, not the CLI wiring.
    # Keeping a minimal runnable entrypoint without assuming real behavior.
    result = main(item=None)
    print(json.dumps(result, default=str))
